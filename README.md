# movoa-nim

Unlimited AI video generator with sound: on paid plans the tenth take of a shot costs what the first did, and your first clip is free to make right now. Official Nim SDK for [Movoa](https://movoa.ai/?utm_source=nimble&utm_medium=package): generate video clips with sound from text or animate a photo as the first frame.

## Install

```bash
nimble install movoa
```

Set `MOVOA_API_KEY` from [movoa.ai/settings/apikeys](https://movoa.ai/settings/apikeys). Runs cost credits on your Movoa account at [movoa.ai/pricing](https://movoa.ai/pricing).

## Usage

```nim
import movoa

let client = newClient()
let url = client.generateVideo("a paper boat drifting down a rain gutter, low angle")
echo url
```

To animate a still photo as the first frame:

```nim
let url = client.generateVideo("the camera slowly orbits the statue", imageUrl = "https://example.com/statue.jpg")
```

## Links

- [Movoa](https://movoa.ai/?utm_source=nimble&utm_medium=package)
- [Text to video](https://movoa.ai/video/text-to-video)
- [API keys](https://movoa.ai/settings/apikeys)
- [Pricing](https://movoa.ai/pricing)
