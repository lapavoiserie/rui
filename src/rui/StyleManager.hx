package rui;

class StyleManager {
	public static function inject(css:String):Void {
		#if js
		var doc = js.Browser.document;
		var style = doc.createStyleElement();
		style.innerHTML = css;
		doc.head.appendChild(style);
		#elseif sys
		// No-op or print for sys targets?
		// Maybe we could save to a file if needed, but for now just ignore.
		trace("[StyleManager] CSS Injection not supported on this target: " + css);
		#end
	}
}
