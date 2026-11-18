## Official Nim SDK for Movoa (https://movoa.ai).
## Unlimited AI video generator with sound: on paid plans the tenth take of a shot
## costs what the first did, and your first clip is free to make right now.

import std/[httpclient, json, os, strutils, times]

const
  BaseUrl* = "https://movoa.ai"
  KeysUrl* = BaseUrl & "/settings/apikeys"
  DefaultModel* = "minimax-h3"
  SdkVersion* = "0.1.0"

type
  ErrorKind* = enum
    ekAuth = "auth"
    ekQuota = "quota"
    ekPlan = "plan"
    ekBusy = "busy"
    ekRejected = "rejected"
    ekGeneration = "generation"
    ekTimeout = "timeout"
    ekApi = "api"

  MovoaError* = object of CatchableError
    kind*: ErrorKind
    httpStatus*: int
    code*: int
    reason*: string
    taskId*: string

  TaskStatus* = object
    id*: string
    status*: string
    videos*: seq[string]
    errorMessage*: string
    failureKind*: string
    queued*: bool
    queueEta*: float
    raw*: JsonNode

  MovoaClient* = ref object
    apiKey*: string
    baseUrl*: string
    timeoutMs*: int
    pollMs*: int

proc newClient*(apiKey = "", baseUrl = ""): MovoaClient =
  let k = if apiKey.len > 0: apiKey.strip() else: getEnv("MOVOA_API_KEY").strip()
  let b = if baseUrl.len > 0: baseUrl.strip(trailing = true, chars = {'/'})
          else: getEnv("MOVOA_BASE_URL", BaseUrl).strip(trailing = true, chars = {'/'})
  MovoaClient(apiKey: k, baseUrl: b, timeoutMs: 30 * 60 * 1000, pollMs: 10 * 1000)

proc raiseMovoa(kind: ErrorKind, msg: string, httpStatus = 0, code = 0, reason = "", taskId = "") {.noreturn.} =
  var e = newException(MovoaError, msg)
  e.kind = kind
  e.httpStatus = httpStatus
  e.code = code
  e.reason = reason
  e.taskId = taskId
  raise e

proc classify*(httpStatus: int, body: string): tuple[kind: ErrorKind, msg: string, code: int, reason: string] =
  var j: JsonNode
  try:
    j = parseJson(body)
  except CatchableError:
    let k = if httpStatus == 401: ekAuth else: ekApi
    return (k, "HTTP " & $httpStatus, 0, "")
  let code = if j.kind == JObject and j.hasKey("code"): j["code"].getInt() else: 0
  let msg = if j.kind == JObject and j.hasKey("message"): j["message"].getStr() else: ""
  var reason = ""
  if j.kind == JObject and j.hasKey("data") and j["data"].kind == JObject and j["data"].hasKey("reason"):
    reason = j["data"]["reason"].getStr()

  if httpStatus == 401 or "no auth" in msg.toLowerAscii():
    return (ekAuth, if msg.len > 0: msg else: "Invalid API key", code, reason)
  if reason == "insufficient_credits":
    return (ekQuota, if msg.len > 0: msg else: "Insufficient credits", code, reason)
  if reason == "plan_required":
    return (ekPlan, if msg.len > 0: msg else: "Paid plan required", code, reason)
  if reason == "concurrency":
    return (ekBusy, if msg.len > 0: msg else: "Too many concurrent runs", code, reason)
  if code == -2 or code == -3:
    return (ekRejected, if msg.len > 0: msg else: "Prompt rejected", code, reason)
  (ekApi, if msg.len > 0: msg else: "HTTP " & $httpStatus, code, reason)

proc postJson(c: MovoaClient, path: string, payload: JsonNode): JsonNode =
  if c.apiKey.len == 0:
    raiseMovoa(ekAuth, "MOVOA_API_KEY is not set")
  let client = newHttpClient(timeout = 60000)
  defer: client.close()
  client.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Authorization": "Bearer " & c.apiKey,
    "User-Agent": "movoa-nim/" & SdkVersion
  })
  let resp = client.request(c.baseUrl & path, httpMethod = HttpPost, body = $payload)
  let status = resp.code.int
  var j: JsonNode
  try:
    j = parseJson(resp.body)
  except CatchableError:
    let cinfo = classify(status, resp.body)
    raiseMovoa(cinfo.kind, cinfo.msg, status, cinfo.code, cinfo.reason)
  let code = if j.kind == JObject and j.hasKey("code"): j["code"].getInt() else: -1
  if status >= 400 or code != 0:
    let cinfo = classify(status, resp.body)
    raiseMovoa(cinfo.kind, cinfo.msg, status, cinfo.code, cinfo.reason)
  if j.hasKey("data"): j["data"] else: newJObject()

proc buildBody*(prompt: string, imageUrl = "", options = newJObject()): JsonNode =
  var opts = if options.kind == JObject: copy(options) else: newJObject()
  opts["sound"] = %true
  var scene = "text-to-video"
  if imageUrl.len > 0:
    opts["image_input"] = %*[imageUrl]
    scene = "image-to-video"
  %*{
    "provider": "auto",
    "mediaType": "video",
    "model": DefaultModel,
    "scene": scene,
    "prompt": prompt,
    "options": opts
  }

proc submit*(c: MovoaClient, prompt: string, imageUrl = "", options = newJObject()): string =
  if prompt.strip().len == 0:
    raiseMovoa(ekApi, "prompt is required")
  let d = c.postJson("/api/ai/generate", buildBody(prompt, imageUrl, options))
  if not d.hasKey("id") or d["id"].getStr().len == 0:
    raiseMovoa(ekApi, "movoa.ai returned no task id")
  d["id"].getStr()

proc status*(c: MovoaClient, taskId: string): TaskStatus =
  let d = c.postJson("/api/ai/query", %*{"taskId": taskId})
  var vids: seq[string] = @[]
  if d.hasKey("videos") and d["videos"].kind == JArray:
    for v in d["videos"]:
      if v.kind == JString: vids.add(v.getStr())
  TaskStatus(
    id: if d.hasKey("id"): d["id"].getStr() else: taskId,
    status: if d.hasKey("status"): d["status"].getStr() else: "",
    videos: vids,
    errorMessage: if d.hasKey("errorMessage") and d["errorMessage"].kind == JString: d["errorMessage"].getStr() else: "",
    failureKind: if d.hasKey("failureKind") and d["failureKind"].kind == JString: d["failureKind"].getStr() else: "",
    queued: d.hasKey("queued") and d["queued"].kind == JBool and d["queued"].getBool(),
    queueEta: if d.hasKey("queueEta") and d["queueEta"].kind in {JInt, JFloat}: d["queueEta"].getFloat() else: 0.0,
    raw: d
  )

proc credits*(c: MovoaClient): int =
  let d = c.postJson("/api/user/get-user-credits", newJObject())
  if d.hasKey("remainingCredits"): d["remainingCredits"].getInt() else: 0

proc waitFor*(c: MovoaClient, taskId: string): string =
  let deadline = getTime() + initDuration(milliseconds = c.timeoutMs)
  while true:
    let t = c.status(taskId)
    if t.status == "success":
      if t.videos.len == 0:
        raiseMovoa(ekGeneration, "finished with no video", taskId = taskId)
      return t.videos[0]
    if t.status == "failed" or t.status == "canceled":
      let why = if t.errorMessage.len > 0: t.errorMessage else: t.status
      raiseMovoa(ekGeneration, why, taskId = taskId)
    if getTime() >= deadline:
      raiseMovoa(ekTimeout, "still generating", taskId = taskId)
    sleep(c.pollMs)

proc generateVideo*(c: MovoaClient, prompt: string, imageUrl = "", options = newJObject()): string =
  c.waitFor(c.submit(prompt, imageUrl, options))
