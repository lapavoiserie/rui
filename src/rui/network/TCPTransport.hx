package rui.network;

import sys.net.Socket;
import sys.net.Host;
import haxe.io.Error;
import rui.network.Transport;

class TCPTransport implements Transport {
	var socket:Socket;
	var listener:TransportListener;
	var running:Bool = false;

	public function new() {}

	public function setListener(listener:TransportListener):Void {
		this.listener = listener;
	}

	public function connect(url:String):Void {
		// Expects url in format "host:port" e.g. "localhost:8080"
		var parts = url.split(":");
		if (parts.length != 2) {
			if (listener != null)
				listener.onError("Invalid URL format. Use host:port");
			return;
		}

		var host = parts[0];
		var port = Std.parseInt(parts[1]);

		try {
			socket = new Socket();
			socket.connect(new Host(host), port);
			running = true;
			if (listener != null)
				listener.onOpen();

			// Start reading loop in a thread
			#if sys
			sys.thread.Thread.create(readLoop);
			#end
		} catch (e:Dynamic) {
			if (listener != null)
				listener.onError("Connection failed: " + Std.string(e));
		}
	}

	function readLoop():Void {
		while (running) {
			try {
				if (socket == null)
					break;
				var line = socket.input.readLine();
				trace("TCPTransport: Received line: " + line);
				if (listener != null)
					listener.onMessage(line);
			} catch (e:haxe.io.Eof) {
				trace("TCPTransport: EOF");
				running = false;
				if (listener != null)
					listener.onClose();
				break;
			} catch (e:Dynamic) {
				trace("TCPTransport: Error: " + Std.string(e));
				running = false;
				if (listener != null)
					listener.onError("Read error: " + Std.string(e));
				break;
			}
		}
	}

	public function send(data:String):Void {
		if (socket == null || !running)
			return;
		try {
			trace("TCPTransport: Sending: " + data);
			socket.output.writeString(data + "\n");
			socket.output.flush();
		} catch (e:Dynamic) {
			if (listener != null)
				listener.onError("Send error: " + Std.string(e));
		}
	}
}
