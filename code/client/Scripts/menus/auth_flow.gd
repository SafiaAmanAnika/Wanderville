extends RefCounted
## Username/password and system-browser Google share session/profile loading.
static func complete(response: Dictionary) -> Dictionary:
	if not response.get("ok",false): return response
	var data: Variant=APIClient.data_of(response)
	if not data is Dictionary or str(data.get("access_token","")).is_empty() or not data.get("player") is Dictionary:
		return {"ok":false,"message":"Sign-in returned incomplete account data. Please try again."}
	Global.set_session(str(data.access_token),data.player,str(data.get("refresh_token","")))
	var version := Global.session_version
	var me: Dictionary=await APIClient.me(Global.token)
	if not me.get("ok",false): return me
	if not await GameState.load_from_backend(): return {"ok":false,"message":GameState.last_error}
	if version!=Global.session_version: return {"ok":false,"stale":true,"message":"The signed-in account changed."}
	return {"ok":true}
