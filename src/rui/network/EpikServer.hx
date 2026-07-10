package rui.network;

import sys.net.Socket;
import sys.net.Host;
import rui.network.NetworkManager.NetworkMessage;

class EpikServer {
	var server:Socket;
	var clients:Array<ServerClient> = [];
	var rooms:Map<String, Array<ServerClient>> = [];
	var port:Int;

	public function new() {
		server = new Socket();
	}

	public function start(port:Int) {
		this.port = port;
		try {
			server.bind(new Host("0.0.0.0"), port);
			server.listen(10);
			trace('EpikServer started on port $port');

			while (true) {
				var socket = server.accept();
				trace("Client connected");
				var client = new ServerClient(this, socket);
				clients.push(client);
			}
		} catch (e:Dynamic) {
			trace("Server error: " + e);
		}
	}

	public function joinRoom(client:ServerClient, room:String):Void {
		if (client.room != null) {
			leaveRoom(client);
		}
		client.room = room;
		if (!rooms.exists(room))
			rooms.set(room, []);
		rooms.get(room).push(client);
		trace('Client joined room: $room');
		// Send confirmation
		var welcome = {
			type: "CHAT",
			content: "Server: Welcome to " + room
		};
		client.send(haxe.Json.stringify(welcome));

		// Broadcast USER_JOINED to others to trigger sync
		var joinMsg = {
			type: "USER_JOINED",
			room: room,
			id: "unknown" // In a real app we'd have user IDs
		};
		broadcast(client, haxe.Json.stringify(joinMsg));
	}

	public function leaveRoom(client:ServerClient):Void {
		if (client.room != null && rooms.exists(client.room)) {
			rooms.get(client.room).remove(client);
		}
		clients.remove(client);
	}

	public function broadcast(sender:ServerClient, msg:String):Void {
		if (sender.room == null || !rooms.exists(sender.room))
			return;

		for (c in rooms.get(sender.room)) {
			if (c != sender) {
				c.send(msg);
			}
		}
	}
}

class ServerClient {
	public var socket:Socket;
	public var room:String;
	public var isWebSocket:Bool = false;

	var server:EpikServer;

	public function new(server:EpikServer, s:Socket) {
		this.server = server;
		this.socket = s;
		this.socket.setBlocking(true);
		#if sys
		sys.thread.Thread.create(readLoop);
		#end
	}

	function readLoop():Void {
		try {
			// Initial protocol detection
			var firstLine = socket.input.readLine();
			if (StringTools.startsWith(firstLine, "GET")) {
				// WebSocket Handshake
				doHandshake(firstLine);
				isWebSocket = true;
				trace("Client upgraded to WebSocket");

				// WS Read Loop
				while (true) {
					var msg = readWebSocketFrame();
					handleMessage(msg);
				}
			} else {
				// Raw TCP Read Loop
				handleMessage(firstLine); // Process the first line we already read
				while (true) {
					var line = socket.input.readLine();
					handleMessage(line);
				}
			}
		} catch (e:Dynamic) {
			trace("Client disconnected: " + e);
			server.leaveRoom(this);
			try
				socket.close()
			catch (e:Dynamic) {};
		}
	}

	function handleMessage(jsonStr:String) {
		if (jsonStr == null || jsonStr.length == 0)
			return;
		// trace("Received: " + jsonStr);
		try {
			var msg:NetworkMessage = haxe.Json.parse(jsonStr);
			if (msg.type == "JOIN") {
				server.joinRoom(this, msg.room);
			} else {
				server.broadcast(this, jsonStr);
			}
		} catch (e:Dynamic) {
			trace("Error parsing message: " + e + " from " + jsonStr);
		}
	}

	function doHandshake(firstLine:String) {
		var key = "";
		trace("Handshake starting: " + firstLine);
		while (true) {
			var line = socket.input.readLine();
			// trace("Handshake header: " + line);
			if (StringTools.trim(line) == "")
				break; // End of headers
			if (StringTools.startsWith(line, "Sec-WebSocket-Key: ")) {
				key = StringTools.trim(line.substr(19));
				trace("Found Key: " + key);
			}
		}

		if (key != "") {
			// trace("Handshake Key: " + key);
			var magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
			var sha1 = haxe.crypto.Sha1.encode(key + magic);
			var accept = haxe.crypto.Base64.encode(haxe.io.Bytes.ofHex(sha1));
			trace("Generated Accept: " + accept);

			var res = "HTTP/1.1 101 Switching Protocols\r\n" + "Upgrade: websocket\r\n" + "Connection: Upgrade\r\n" + "Sec-WebSocket-Accept: " + accept
				+ "\r\n\r\n";
			socket.output.writeString(res);
			socket.output.flush();
			trace("Handshake response sent.");
		} else {
			trace("Handshake failed: No Sec-WebSocket-Key found");
		}
	}

	function readWebSocketFrame():String {
		var input = socket.input;
		var b0 = input.readByte();
		var b1 = input.readByte();

		// var finalFrag = (b0 & 0x80) != 0;
		var opcode = b0 & 0x0F;
		var masked = (b1 & 0x80) != 0;
		var payloadLen = b1 & 0x7F;

		if (opcode == 8)
			throw "Client closed connection"; // Close frame

		if (payloadLen == 126) {
			var b2 = input.readByte();
			var b3 = input.readByte();
			payloadLen = (b2 << 8) | b3;
		} else if (payloadLen == 127) {
			// Verify logic for 64-bit length needed for huge frames,
			// checking high bytes are 0 for simplicity in this demo.
			for (i in 0...4)
				input.readByte(); // Skip high 32 bits
			var b4 = input.readByte();
			var b5 = input.readByte();
			var b6 = input.readByte();
			var b7 = input.readByte();
			payloadLen = (b4 << 24) | (b5 << 16) | (b6 << 8) | b7;
		}

		var maskKey = haxe.io.Bytes.alloc(4);
		if (masked) {
			maskKey.set(0, input.readByte());
			maskKey.set(1, input.readByte());
			maskKey.set(2, input.readByte());
			maskKey.set(3, input.readByte());
		}

		var payload = haxe.io.Bytes.alloc(payloadLen);
		input.readBytes(payload, 0, payloadLen);

		if (masked) {
			for (i in 0...payloadLen) {
				payload.set(i, payload.get(i) ^ maskKey.get(i % 4));
			}
		}

		return payload.toString();
	}

	public function send(msg:String):Void {
		try {
			// trace("Broadcasting: " + msg);
			if (isWebSocket) {
				sendWebSocketFrame(msg);
			} else {
				socket.output.writeString(msg + "\n");
				socket.output.flush();
			}
		} catch (e:Dynamic) {
			trace("Send error: " + e);
		}
	}

	function sendWebSocketFrame(msg:String) {
		try {
			var bytes = haxe.io.Bytes.ofString(msg);
			var len = bytes.length;
			var output = socket.output;

			output.writeByte(0x81); // Text frame, final

			if (len <= 125) {
				output.writeByte(len);
			} else if (len <= 65535) {
				output.writeByte(126);
				output.writeByte((len >> 8) & 0xFF);
				output.writeByte(len & 0xFF);
			} else {
				output.writeByte(127);
				// Write 64-bit length (assume < 4GB for now)
				output.writeInt32(0);
				output.writeInt32(len);
			}

			output.write(bytes);
			output.flush();
			trace("WS Frame sent.");
		} catch (e:Dynamic) {
			trace("WS Send Error: " + e);
		}
	}
}
