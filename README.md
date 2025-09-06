# Anki Lyrics Note Generator

Turn a folder of plain-text lyrics into Anki <q>what’s the next line?</q> flashcards.

## Sample card

```txt
Front:
Hey Jude, don't make it bad
Take a sad song and make it better

Back:
Remember to let her into your heart
```

## Quick start

```bash
swift build -c release
.build/release/AnkiLyricsNoteGenerator /path/to/lyrics
```

## Prepare lyrics

* One text file per song
* One lyric line per line, e.g.:
  ```txt
  /path/to/lyrics/
  ├── Hey Jude.txt
  ├── Hallelujah.txt
  └── Yesterday.txt
  ```

## What you get

* `_notes.csv` in the same folder
* Two fields (no header): Front, Back
* Front shows the previous 2 lines; Back is the next line

### Example

**Input (`Hey Jude.txt`)**

```txt
Hey Jude, don't make it bad
Take a sad song and make it better
Remember to let her into your heart
Then you can start to make it better
```

**Output (`_notes.csv`, snippet)**

```csv
"<small>Hey Jude</small><br>Hey Jude, don't make it bad","Take a sad song and make it better"
"<small>Hey Jude</small><br>Hey Jude, don't make it bad<br>Take a sad song and make it better","Remember to let her into your heart"
```

## Import to Anki

1. **File → Import** → select `_notes.csv`
2. Type: **CSV/TXT**, allow **HTML in fields**
3. Map **Field 1 → Front**, **Field 2 → Back**
4. Choose a deck and import
