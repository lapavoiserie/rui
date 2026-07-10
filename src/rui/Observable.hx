package rui;

import haxe.macro.Context;
import haxe.macro.Expr;

@:autoBuild(rui.ObservableMacro.build())
interface Observable {
	public var uuid(get, never):String;
	function subscribe(listener:Void->Void):Void;
	function unsubscribe(listener:Void->Void):Void;
	function onPropChange(listener:(String, Dynamic) -> Void):Void;
}
