class_name HmacSign
extends RefCounted


static func sha256_hex(body: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body.to_utf8_buffer())
	return ctx.finish().hex_encode()


static func sign(secret: PackedByteArray, method: String, path: String, timestamp: String, nonce: String, body: String) -> String:
	var canonical := "%s\n%s\n%s\n%s\n%s" % [
		method, path, timestamp, nonce, sha256_hex(body)
	]
	var hmac := HMACContext.new()
	hmac.start(HashingContext.HASH_SHA256, secret)
	hmac.update(canonical.to_utf8_buffer())
	return hmac.finish().hex_encode()
