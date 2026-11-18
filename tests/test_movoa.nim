import std/[json, os]
import ../src/movoa

doAssert classify(401, """{"code":-1,"message":"Invalid API key"}""").kind == ekAuth
doAssert classify(200, """{"code":-1,"message":"no auth"}""").kind == ekAuth
doAssert classify(200, """{"code":-1,"message":"err","data":{"reason":"insufficient_credits"}}""").kind == ekQuota
doAssert classify(200, """{"code":-1,"message":"err","data":{"reason":"plan_required"}}""").kind == ekPlan
doAssert classify(200, """{"code":-1,"message":"err","data":{"reason":"concurrency"}}""").kind == ekBusy
doAssert classify(200, """{"code":-2,"message":"blocked"}""").kind == ekRejected
doAssert classify(502, """{"code":-1,"message":"upstream"}""").kind == ekApi

let b = buildBody("a paper boat", "https://example.com/boat.jpg", %*{"duration": 6, "aspect_ratio": "9:16"})
doAssert b["model"].getStr() == "minimax-h3"
doAssert b["scene"].getStr() == "image-to-video"
doAssert b["options"]["sound"].getBool() == true
doAssert b["options"]["duration"].getInt() == 6

try:
  discard newClient(" ").submit("x")
  doAssert false, "expected auth error"
except MovoaError as e:
  doAssert e.kind == ekAuth

if getEnv("MOVOA_LIVE") == "1":
  try:
    discard newClient("invalid-test-fixture-token").submit("a quiet harbor at dawn")
    doAssert false, "expected live auth error"
  except MovoaError as e:
    echo "live wrong key -> ", e.kind
    doAssert e.kind == ekAuth

echo "all nim tests passed"
