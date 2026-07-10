package rui.network;

import rui.Observable;
import rui.network.Transport;
import Type;

typedef NetworkMessage = {
	var type:String; // "JOIN", "SYNC", "FULL_SYNC", "OBS_REF"
	@:optional var room:String;
	@:optional var id:String;
	@:optional var prop:String;
	@:optional var value:Dynamic;
	@:optional var state:Dynamic;
	@:optional var className:String; // For OBS_REF
}

interface NetworkListener {
	function onConnected():Void;
	function onDisconnected():Void;
	function onError(msg:String):Void;
	function onMessage(msg:String):Void;
}

class NetworkManager implements TransportListener {
	var transport:Transport;
	var observables:Map<String, Observable> = [];
	var _isApplyingUpdate:Bool = false;
	var _listeners:Array<NetworkListener> = [];

	public function new(transport:Transport) {
		this.transport = transport;
		this.transport.setListener(this);
	}

	public function addListener(l:NetworkListener) {
		_listeners.push(l);
	}

	public function connect(url:String):Void {
		transport.connect(url);
	}

	public function join(room:String):Void {
		var msg:NetworkMessage = {type: "JOIN", room: room};
		send(msg);
	}

	public function register(id:String, obs:Observable):Void {
		if (observables.exists(id))
			return;
		observables.set(id, obs);
		trace('NetworkManager: Registered $id');

		// Recursive scan
		var fields = Reflect.fields(obs);
		for (field in fields) {
			try {
				var val = Reflect.getProperty(obs, field);
				if (Std.isOfType(val, Observable)) {
					var childObs:Observable = cast val;
					register(childObs.uuid, childObs);
				}
			} catch (e:Dynamic) {}
		}

		obs.onPropChange(function(prop:String, val:Dynamic) {
			if (_isApplyingUpdate)
				return;

			if (Std.isOfType(val, Observable)) {
				// Child replaced or set
				var childObs:Observable = cast val;
				register(childObs.uuid, childObs); // Ensure it is registered

				var msg:NetworkMessage = {
					type: "OBS_REF",
					id: id,
					prop: prop,
					value: childObs.uuid,
					className: Type.getClassName(Type.getClass(childObs))
				};
				trace('NetworkManager: Sending OBS_REF for $prop');
				send(msg);
			} else {
				var msg:NetworkMessage = {
					type: "SYNC",
					id: id,
					prop: prop,
					value: val
				};
				send(msg);
			}
		});
	}

	public function sendRaw(msg:String):Void {
		transport.send(msg);
	}

	function send(msg:NetworkMessage):Void {
		var str = haxe.Json.stringify(msg);
		transport.send(str);
	}

	// TransportListener
	public function onOpen():Void {
		trace("Connected");
		for (l in _listeners)
			l.onConnected();
	}

	public function onClose():Void {
		trace("Disconnected");
		for (l in _listeners)
			l.onDisconnected();
	}

	public function onError(msg:String):Void {
		trace("Error: " + msg);
		for (l in _listeners)
			l.onError(msg);
	}

	public function onMessage(data:String):Void {
		try {
			for (l in _listeners)
				l.onMessage(data);
			var msg:NetworkMessage = haxe.Json.parse(data);
			handleMessage(msg);
		} catch (e:Dynamic) {
			trace("Failed to parse message: " + data);
		}
	}

	function handleMessage(msg:NetworkMessage):Void {
		trace("NetworkManager: Handling message: " + msg.type);
		switch (msg.type) {
			case "SYNC":
				trace('NetworkManager: SYNC id=${msg.id} prop=${msg.prop} val=${msg.value}');
				applyUpdate(msg.id, msg.prop, msg.value);

			case "OBS_REF":
				trace('NetworkManager: OBS_REF id=${msg.id} prop=${msg.prop} childUUID=${msg.value}');
				if (msg.value == null) {
					applyUpdate(msg.id, msg.prop, null);
					return;
				}

				var childUUID:String = msg.value;
				if (observables.exists(childUUID)) {
					// Child already exists locally
					applyUpdate(msg.id, msg.prop, observables.get(childUUID));
				} else {
					// Create new instance
					trace('NetworkManager: Creating new instance of ${msg.className}');
					var cls = Type.resolveClass(msg.className);
					if (cls != null) {
						var instance:Dynamic = Type.createInstance(cls, []);
						if (Std.isOfType(instance, Observable)) {
							// We need to force set the UUID to match the server's UUID
							// But UUID is read-only public, private write.
							// We can use Reflect to set private field `__uuid` or just assume it syncs?
							// Actually, `Observable` macro generates `__uuid` field.
							Reflect.setField(instance, "__uuid", childUUID);
							register(childUUID, instance);
							applyUpdate(msg.id, msg.prop, instance);
						}
					} else {
						trace("NetworkManager: Class not found: " + msg.className);
					}
				}

			case "FULL_SYNC":
				trace('NetworkManager: FULL_SYNC id=${msg.id} prop=${msg.prop} val=${msg.value}');
				applyUpdate(msg.id, msg.prop, msg.value);

			case "USER_JOINED":
				for (id => obs in observables) {
					var fields = Reflect.fields(obs);
					for (field in fields) {
						try {
							// SKIP internal fields and accessors
							if (StringTools.startsWith(field, "__")
								|| StringTools.startsWith(field, "set_")
								|| StringTools.startsWith(field, "get_"))
								continue;

							var val = Reflect.getProperty(obs, field);
							// SKIP functions
							if (Reflect.isFunction(val))
								continue;

							send({
								type: "FULL_SYNC",
								id: id,
								prop: field,
								value: val
							});
						} catch (e:Dynamic) {}
					}
				}
		}
	}

	function applyUpdate(id:String, prop:String, val:Dynamic):Void {
		if (id != null && prop != null && observables.exists(id)) {
			var obs = observables.get(id);
			_isApplyingUpdate = true;
			try {
				Reflect.setProperty(obs, prop, val);
			} catch (e:Dynamic) {
				trace("NetworkManager: Reflect Error: " + e);
			}
			_isApplyingUpdate = false;
		}
	}
}
