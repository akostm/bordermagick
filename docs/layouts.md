# Writing layouts

> **Preview.** The layout format is new in bordermagick 1.3 and may still change in 1.x releases.
> Built-in layouts are updated along with it; your own may need small edits after an update.

Every border style is a **layout file**: how wide each side of the frame is, what the background looks
like, and which text, logo or decoration goes where. The built-in ones are in [`layouts/`](../layouts),
and you can write your own. The format is plain text, close to an INI file, with property names and
values borrowed from CSS. Everything scales with the photo, so a layout looks the same at any resolution.

---

## 1. Quick start

Save this as `~/.bordermagick/layouts/stamped.layout`:

```ini
# The classic strip, plus an orange date stamp in the photo's corner
[layout]
extends     = standard
category    = Mine
description = The classic strip with a date stamp on the photo

[text stamp]
cell    = photo bottom-right
margin  = 0 3pmin 3pmin 0
font    = 3pmin DIN Condensed
color   = #FF8A1E
content = {date:'%y %m %d}
```

Then:

```bash
bordermagick -b stamped photo.jpg       # frame with it
bordermagick -h                         # it's listed under "Mine"
```

**Tools:**
- `bordermagick --layouts` lists every layout and whether it's built in or yours.
- `bordermagick --dump-layout stamped` shows the layout with everything it inherits, or the first error,
  with its file and line.
- `bordermagick --tags photo.jpg` shows every value a layout can print for that photo.
- `bordermagick --plan -b stamped photo.jpg` prints where each element goes, in pixels, without writing
  anything.

**Where layouts are found:**
1. `~/.bordermagick/layouts/<name>.layout` (or in `$BORDERMAGICK_HOME/layouts`): yours.
2. `layouts/<name>.layout` next to the script: the built-in ones.

A layout of yours with the same name as a built-in one replaces it, also for the layouts that extend it.
It can still build on the one it replaces: your `museum.layout` with `extends = museum` extends the
built-in museum.

---

## 2. Concepts

```
┌──────────────────── frame: padding = border widths, background, texture ──────┐
│                                 top  (band)                                    │
│   ┌─────────┬───────────────────────────────────────────────┬─────────┐       │
│   │  left   │                     photo                     │  right  │       │
│   │ (band)  │   9 anchors, drawn on top of the picture      │ (band)  │       │
│   │         │   (captions, stamps, rectangles)              │         │       │
│   └─────────┴───────────────────────────────────────────────┴─────────┘       │
│                                bottom  (band)                                  │
└────────────────────────────────────────────────────────────────────────────────┘
```

- **Frame:** the whole output image. Its `padding` sets the border width on each side.
- **Regions:**
  - The four **bands** (`top`, `bottom`, `left`, `right`) are the borders around the photo. Top and
    bottom span the photo's width, left and right its height.
  - **`photo`** is the picture itself, for anything drawn on it.
- **Bands and the photo:**
  - Each band is a small grid of **columns** and, if needed, **rows**.
  - The photo has nine **anchors**: `top-left`, `top-center`, `top-right`, `left`, `center`, `right`,
    `bottom-left`, `bottom-center`, `bottom-right`.
- **Items:** text, the maker's logo, rules, rectangles and the contact sheet's edge print.
  - Each item sits in a **cell**: a column of a band (or a span of columns, in a row), or a photo anchor.
  - Items in the same cell stack top to bottom in file order.
  - An item with `position = absolute` is placed by distances from its region's edges instead.

---

## 3. File format

```ini
# A comment
[frame]                 # a section
padding = 3pmin
[text title]            # an item: type and name
content = {title}
```

- **One `key = value` per line.**
  - Whitespace around `=` and at both ends is ignored.
  - There are no multi-line values.
  - Double quotes around a value keep leading or trailing spaces.
- **Comments:** a line starting with `#`, or ` # …` after a value. A comment needs whitespace before the
  `#` and whitespace or the end of the line after it, so colours like `#FBFAF6` stay values.
- **Names:** section, item and key names are lower case, using `a–z`, `0–9` and `-`. Item names are
  unique within a layout.
- **Files:** a layout is one UTF-8 file named `<name>.layout`.
- **Errors:** unknown sections, item types and keys are errors, so typos are caught. Errors name the
  file and line.

---

## 4. Lengths

| Unit | Means |
|---|---|
| `pmin` | 1% of the photo's short side: the usual unit, so a frame looks the same at any size |
| `pw`, `ph` | 1% of the photo's width or height |
| `fw` | 1% of the frame's width (not in the left and right padding, which decide it) |
| `em` | the item's font size |
| `%` | of the space the item has: its cell, or its region (not for padding or font sizes) |
| `px` | output pixels, at the photo's full resolution |
| `fr` | a share of the space left over (column and row sizes only) |

- **Decimals** are fine: `2.6pmin`.
- **Sums and divisions:** a length can be a sum of terms, each optionally divided by a whole number:
  `5.5pmin+1pmin`, `1em/3`, `3pw-0.5em`, `1fw/6+2px`. Each term is rounded down on its own.
- **Four-sided values** (`padding`, `margin`, `inset`) take CSS shorthand: `14pmin`, `14pmin 26pmin`,
  `14pmin 14pmin 26pmin` or `top right bottom left`.
- **Font sizes** take `pmin`, `pw`, `ph`, `fw` or `px`.

---

## 5. Sections

### `[layout]`

| Key | Meaning |
|---|---|
| `name` | optional; if set, it must match the file name |
| `category` | the group it's listed under in `-h` (`Stone`, `Print`, or your own) |
| `description` | one line for `-h` and `--layouts` |
| `extends` | a layout to start from (§8) |

### `[frame]`

| Key | Values | Default |
|---|---|---|
| `padding` | the border widths; the top or bottom may be `auto`, to be as tall as its band's content | `0` |
| `background` | see below | `white` |
| `texture` | `paper` (strength from `-p`), `paper <0–30>`, `paper $paper/3`, or `none` | `none` |
| `text-effect` | `engrave`: text and logo cut into the surface (a shadow up-left, a highlight down-right) | `none` |
| text properties | defaults for every item (§7) | `1.7pmin DIN Alternate`, `color = auto` |

**Backgrounds:**
- **A colour:** anything ImageMagick knows, like `#F3F0E8`, `navy` or `rgb(40,60,90)`. `$border` is the
  colour given with `-b`.
- **`gradient(<colour>, <colour>[, <angle>])`:** two colours, by default diagonally from top left to
  bottom right (135°).
- **`auto`:** the photo's average colour, lifted to a light pastel.
- **`dominant`:** the photo's most common colour, deepened.
- **`material(…)`:** `marble`, `marble-dark`, `marble-green`, `marble-beige`, `terrazzo` or `linen`.
  Terrazzo keeps its chips off the text.
- **`frost(light)` and `frost(dark)`:** the photo itself, blurred behind frosted glass.
- **`film`:** the contact sheet's near-black.

### `[photo]`

| Key | Values |
|---|---|
| `effect` | `none`; `inset` (set into stone); `drop-shadow` (floating above the glass); `bevel <width> <colour>` (a mat's bevelled opening) |

### `[top]`, `[bottom]`, `[left]`, `[right]`: bands

| Key | Values | Default |
|---|---|---|
| `columns` | column widths: lengths, `%`, `fr`, `auto` (as wide as its content), e.g. `1fr auto`, `28% 44% 1fr` | `1fr` |
| `rows` | row heights: lengths, `fr`, `auto`, e.g. `auto auto auto` | one `auto` row |
| `column-gap`, `row-gap` | lengths | `0` |
| `padding` | inner spacing, CSS shorthand | `0` |
| `align-items` | where a cell's stack sits: `start`, `center`, `end` | `center` |
| text properties | defaults for the band's items (§7) | |

A band is there when its side of the frame's `padding` isn't zero.

### Items: `[<type> <name>]`

**Every item:**

| Key | Values | Default |
|---|---|---|
| `cell` | `bottom 2` (band, column), `bottom 1-3` (columns 1 to 3), `bottom 1-3/2` (row 2), `photo top-center` | `bottom 1` |
| `justify` | `start`, `center`, `end` within the cell | `start` |
| `margin` | space around it, CSS shorthand | `0` |
| `position` | `absolute`: placed with `left`/`right`/`top`/`bottom` from its region's edges | |
| `vertical-align` | absolute text only: `baseline` (`bottom` measures to the baseline) or `text-top` (`top` measures to the top of the letters) | |
| `remove` | `yes` drops an item the layout inherited | |

**Item types:**

| Type | Draws | Own keys |
|---|---|---|
| `text` | text from tags (§6) | `content`, `width`, text properties |
| `logo` | the camera maker's logo (see Logos in the README); left out when there's none | `height`: for wide wordmarks, squarer logos are drawn up to 1.6× taller (default `1.8pmin`) |
| `rule` | a line across its cell | `thickness` (default `0.15pmin`), `color` |
| `rect` | a rectangle `inset` from its region's edges (negative: outside) | `inset`, `fill`, `stroke`, `stroke-width`, `under-photo = yes` |
| `edge-print` | the contact sheet's film-edge line along the top: maker, film, ISO, frame numbers | |

An item that comes out empty (text whose tags have no value, a logo for a maker without one) is left out,
and so is the space it would have taken.

---

## 6. Text content and tags

`content` is a template: `{tag}` inserts a value from the photo. `bordermagick --tags photo.jpg` shows
them all.

| Tag | Example |
|---|---|
| `title` | `Erechtheion` (the photo's Title) |
| `city`, `country` | `Athens`, `Greece` |
| `place` | the city when the photo has a title (otherwise the title falls back to the city) |
| `date` | `5 October 2023` |
| `make`, `model` | `FUJIFILM`, `X-T20` (as the camera writes them) |
| `brand`, `body` | `Fujifilm`, `Fujifilm X-T20` |
| `lens` | `XF18-55mm F2.8-4 R LM OIS` (exiftool's lens database) |
| `focal`, `aperture`, `shutter`, `iso` | `35.8 mm`, `ƒ/11.0`, `1/340s`, `ISO 200` |
| `exposure` | `35.8 mm ∙ ƒ/11.0 ∙ 1/340s ∙ ISO 200` |
| `film` | `Provia` (Fujifilm film simulation) |
| `frame` | the last number in the file name, else the photo's place in the batch |
| `filename` | the file name without its extension |

**Template rules:**
- **Fallbacks:** `{title|city|filename}` takes the first one with a value.
- **Date formats:** `{date:%Y}`, `{date:'%y %m %d}`, any strftime format, in English.
- **Separators:** text between two tags is only written when both have a value.
  - `{place} ∙ {date}` gives `Athens ∙ 5 October 2023`, `Athens` or `5 October 2023`.
  - In a chain, an empty tag takes one separator with it.
  - Text before the first tag and after the last one is always kept.
- **Optional groups:** `[…]` disappears when a tag directly inside it is empty, e.g.
  `Digital photograph[, {brand} {film}]` or `[Shot on {model}]`. Groups can be nested.
- **Line breaks:** `\n` starts a new line; between two tags it's a separator like any other text.
- **Literal characters:** `\{`, `\}`, `\[`, `\]`, `\\`.

---

## 7. Text properties

These can be set on an item, or on its band or the frame as defaults: an item's own value wins, then its
band's, then the frame's.

| Key | Values | Default |
|---|---|---|
| `font` | `[bold] [italic] <size> <family>`, e.g. `bold 2.6pmin Georgia` | `1.7pmin DIN Alternate` |
| `font-family`, `font-size`, `font-weight`, `font-style` | the same, one at a time | |
| `color` | a colour; `auto` (dark or light, whichever reads better on the background), `auto-dim` (the translucent secondary ink), `contrast` (black or white) | `auto` |
| `letter-spacing` | a length, usually in `em` | `0` |
| `line-height` | `1` is the font's natural spacing, `0.82` tighter, `1.25` looser | `1` |
| `text-transform` | `uppercase`, `capitalize`, `none` | `none` |
| `text-shadow` | `<x> <y> <blur> <colour>`, several separated by commas | |
| `text-box-trim` | `start`: the letters begin at the very top of the text's box | `none` |
| `max-width` | the most the text may take of its space | all of it |
| `overflow` | when it's too wide: `wrap`, `shrink` (smaller, on one line), `clip` | `wrap` |
| `width` (text items only) | a block of that width that always wraps, e.g. `100%` | |

**Fonts:**
- **Family names:** macOS font names: `Georgia`, `DIN Alternate`, `DIN Condensed`, any font in
  `/System/Library/Fonts`, `/Library/Fonts` or `~/Library/Fonts`.
- **Font collections:** three faces from them have their own names: `HelveticaNeue-Bold`,
  `HelveticaNeue-Medium`, `Futura-CondExtraBold`.
- **Your own fonts:** put them in `~/.bordermagick/fonts/` as `<family>[ Bold][ Italic].ttf` (or `.otf`).
- **One weight only:** a family with a single weight is used for every weight.

---

## 8. Inheritance and the command line

**`extends = <layout>`:**
- It loads that layout first, then this file on top. Every key set here replaces the inherited one,
  section by section and item by item.
- New items go after the inherited ones.
- `remove = yes` drops an inherited item.
- Chains work: `museum-black` → `museum`. Loops are an error.

**Variables:** `$border` and `$paper` are filled in from the command line:
- **`$border`:** the colour given with `-b`. A preset (`cream`, `sunset` …) is turned into its colour,
  and two colours (`'#FFD6E0-#B5E2FA'`) become a diagonal gradient.
- **`$paper`:** the `-p` strength.

**What `-b` picks:**
1. A layout with that name.
2. Otherwise a colour, a colour preset, two colours or `auto`, drawn with the built-in layout
   **`standard`** (the classic strip) and `$border` set to it.

---

## 9. Examples

The built-in layouts are the best examples; each is short and commented:
- **[`standard`](../layouts/standard.layout):** the classic strip, with text on exact baselines.
- **[`marble`](../layouts/marble.layout):** `standard` plus a material, an engraved finish and an inset
  photo, in four lines.
- **[`museum`](../layouts/museum.layout):** a label stacked in an `auto` column, Georgia in three styles.
- **[`poster`](../layouts/poster.layout):** rows, spans, a rule, text blocks of a fixed width, and an
  `auto` bottom border.
- **[`postcard`](../layouts/postcard.layout):** text on the photo that shrinks to fit, with a shadow.
- **[`cover-red`](../layouts/cover-red.layout):** a rectangle under the photo.

---

## 10. For developers

- **`--plan`** prints one line per box, in pixels, `<kind> <name> x y width height`. For text on a
  baseline the box runs from the top of the letters to the bottom of the descenders. Terrazzo's
  keep-clear areas are listed as `clear` lines.
- **Testing hooks:**
  - `BORDERMAGICK_LAYOUTS=<folder>` adds a folder in front of the search path.
  - `BORDERMAGICK_SEED=<n>` makes the textures repeatable.
- **Where the code is:**
  - `lib/layout.sh` reads the files.
  - `lib/tags.sh` reads the photo and fills in templates.
  - `lib/engine.sh` turns a layout into one ImageMagick command.
- **Tests:** `tests/engine/` has test layouts with their expected plans, checked by `tests/unit.sh`.

---

## 11. Limits and plans

- **The structure is flat on purpose:** frame → band → cell → stack. There's no nesting and there are
  no selectors; shared styles come from the band, the frame or `extends`.
- **Planned:**
  - `image` items (a signature or other PNG);
  - `swatches` (the photo's main colours) and `histogram` items;
  - lining up text baselines across cells.
- **One photo per frame for now.** Collages are planned for 2.0.
