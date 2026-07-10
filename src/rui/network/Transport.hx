package rui.network;

interface Transport {
	function connect(url:String):Void;
	function send(data:String):Void;
	function setListener(listener:TransportListener):Void;
}

interface TransportListener {
	function onOpen():Void;
	function onClose():Void;
	function onMessage(data:String):Void;
	function onError(msg:String):Void;
}
