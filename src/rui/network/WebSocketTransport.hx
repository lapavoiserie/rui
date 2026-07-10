package rui.network;

import rui.network.Transport;
#if js
import js.html.WebSocket;
#end

class WebSocketTransport implements Transport {
	#if js
	var ws:WebSocket;
	#end
	var listener:TransportListener;

	public function new() {}

	public function setListener(listener:TransportListener):Void {
		this.listener = listener;
	}

	public function connect(url:String):Void {
		#if js
		// Standard JS WebSocket
		js.Browser.console.log("WS: Connecting to " + url);
		ws = new WebSocket(url);

		ws.onopen = function(_) {
			js.Browser.console.log("WS: Open");
			if (listener != null)
				listener.onOpen();
		};

		ws.onmessage = function(msg:js.html.MessageEvent) {
			if (listener != null)
				listener.onMessage(msg.data);
		};

		ws.onclose = function(_) {
			js.Browser.console.log("WS: Close");
			if (listener != null)
				listener.onClose();
		};

		ws.onerror = function(err) {
			js.Browser.console.error("WS: Error");
			if (listener != null)
				listener.onError("WebSocket Error");
		};
		#else
		if (listener != null)
			listener.onError("WebSockets not supported on non-JS targets yet (libs required)");
		#end
	}

	public function send(data:String):Void {
		#if js
		if (ws != null) {
			ws.send(data);
		}
		#end
	}
}
