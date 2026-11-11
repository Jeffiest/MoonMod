# Larger textures

`texture_pack.py` makes a texture package for Chronicle in three steps: dump the game's own textures, upscale them,
check the result. The engine keeps a package's pictures at their own size (up to 8 times the texture's, 4096 a side),
so a 4x picture shows 4x the detail on the ground, the walls, the characters and the menus.

The pictures are made from your game disc. Share the tool and the settings you used, not the pictures.

## What you need

- Python 3.10 or later with `numpy` and `Pillow`: `pip install numpy pillow`.
- For a model: `onnxruntime`. `pip install onnxruntime-directml` runs it on any graphics card on Windows,
  `onnxruntime-gpu` on CUDA, plain `onnxruntime` on the processor (slow: minutes for one area, hours for the game).
- An ESRGAN-style upscaling model as an `.onnx` file. None comes with MoonMod. Models trained on PlayStation 2 era
  textures suit the game; any model with one RGB input and a whole-number scale works.

## 1. Dump

```
python tools/textures/texture_pack.py dump --game C:\Games\DarkCloud\darkcloud.exe --out dumps
```

This runs the game without a window through a few of the towns, each dungeon, the menu and the title, on a
scratch save of its own, and writes every texture it loads to `dumps/<texture name>.png`. It never reads or writes
your save, and no package's pictures get into the dump.

A texture is dumped only when the game loads it, so the run above misses most of the game. For the rest, play:

```
python tools/textures/texture_pack.py dump --game C:\Games\DarkCloud\darkcloud.exe --out dumps --play
```

The game starts as usual (with your save and your mods; the dump still holds the game's own pictures). Walk through
what you want to cover, open the menus, then close the game. Run it as often as you like into the same folder.

`--jump <place>` (repeat it) picks the places of the windowless run: `e01`, `e03`, `e04`, `dungeon:0` to `dungeon:6`,
`menu`, `title`, `edit:<map>`. `--data <folder>` names the game's data folder if the game does not find it by itself.
Text pictures are dumped in the language the game is set to.

The game matches a package's picture by texture name alone, and a few names hold a different picture from place to
place: every dungeon has a `frame` of its own, and the towns and the dungeons each have their own `fx_foot`. One
upscaled picture would land on all of them. The windowless run dumps each place apart, so it sees these: it puts
them in `dumps/shared-names/<texture name>.<place>.png`, and `upscale` leaves those names out. A `--play` dump cannot
tell: it keeps the last picture the game loaded under each name, so look at what you upscale from it.

The game itself does the dumping: setting `DC_TEXTURE_DUMP=<folder>` before starting it is all `dump` does.

## 2. Upscale

```
python tools/textures/texture_pack.py upscale --dump dumps --package <save>\mods\me.hires --model model.onnx
```

Each dumped picture is enlarged by the model and written to `<package>/textures/<texture name>.png`. A package with
no `mod.json` gets one (id: the folder's name; `"coop": "local"`, so co-op friends need not have it) and a `main.lua`
that does nothing. Turn the package on in the Mod Manager.

| Option | What it does |
| --- | --- |
| `--model FILE` | The model. Without it the pictures are only resized (Lanczos): good for trying the steps, no new detail. |
| `--scale N` | Keep the pictures at N times the texture's size instead of the model's own scale. |
| `--only GLOB`, `--skip GLOB` | Work on some textures: `--only "e01*"`, `--skip "*fnt*"`. Repeat them. |
| `--edge auto\|wrap\|reflect` | What the model sees past a picture's edge. `wrap` suits tiling ground and walls, `reflect` everything else; `auto` looks at each picture's edges, across and down apart. |
| `--alpha model\|bicubic` | Transparency through the model (crisp cut-outs: leaves, fences, hair) or resized (soft glows, smoke). |
| `--provider dml\|cuda\|cpu` | What runs the model. Falls back to the processor when the one asked for is not installed. |
| `--tile N`, `--overlap N` | The model is given N texels a side at a time, with some context around; lower `--tile` if the graphics card runs out of memory. |
| `--redo` | Upscale again what the package already has. Without it only new or newer dumps are done, so a stopped run picks up where it was. |
| `--id`, `--name`, `--author` | For the `mod.json` it writes. |

What the tool does besides running the model: transparent texels get their neighbours' colour first, so cut-outs have
no dark fringe; pictures are cut into overlapping tiles that are cross-faded, so no seams show; tiling pictures are
given their own far side as context, so they still tile; and in a picture without transparency, pure black stays
exactly where it was, because the game draws some of those (the debug font is one) with pure black as see-through.

Models are trained on photographs and game art, not on letters. Fonts and small menu symbols often come out worse
than they went in: look at them, and leave them out with `--skip` or delete their files from the package.

## 3. Check

```
python tools/textures/texture_pack.py check --package <save>\mods\me.hires --dump dumps
```

One line per picture: its size, the texture's size, and the size the game keeps it at on the desktop and in the
browser. It also names pictures the game will never use (a name that matches no texture, a picture the game loads
another way). Any picture you paint or edit yourself can be checked the same way.

## The rules the game follows

- `textures/<texture name>.png` in an enabled package replaces that texture. The name is the dumped file's, lower case,
  only `a-z`, `0-9`, `_` and `-`. Where two packages hold the same picture, the later one in the load order wins.
- The picture keeps its own size, halved (both sides together) while a side is over 4096 or over 8 times the
  texture's. In the browser: 2048 and 2 times. A picture smaller than the texture is enlarged to it. A picture of
  another shape than the texture is stretched to fit.
- `DC_TEXTURE_SCALE_MAX=<1..64>` changes the 8 (or the browser's 2). `1` shrinks every picture to the texture's own
  size, as the game did before; use it to compare, or on a machine short of video memory.
- A file over 64 MiB or over 16 million pixels is not read.
- `stayframe` (a menu sheet) is dumped but cannot be replaced; the tool leaves it out.
- The game writes `mods: replaced texture <name> from <file> (1024x1024 for 256x256)` to its log for each picture it
  takes.
