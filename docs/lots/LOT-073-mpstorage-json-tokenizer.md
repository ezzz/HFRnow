# LOT-073 — MPStorage JSON tokenizer

- **Module:** HFRModels
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** ezzz/HFRnow#97; review of francoisgn/ios-app_SwiftHFR#33 (read-only history)
- **Depends on:** LOT-062 (`JSONValue`, `JSONNumber`, `MPStorageCodec`, the "numbers keep their exact text" rule)

LOT-062 kept other clients' numbers byte for byte by rewriting every number token of the text into a string
`"<U+E000 U+E001><lexeme>"` before `JSONDecoder`, and back after `JSONEncoder` (`JSONNumberBox`). This lot replaces that
workaround with a tokenizer and a writer that keep number lexemes natively, with the same observable behaviour.
The public API of `JSONValue`, `JSONNumber` and `MPStorageCodec` is unchanged.

## Legacy sources

None for the tokenizer. Legacy read and wrote the document with `NSJSONSerialization` (`Classes/MPStorage.m:884-886`,
`:908-909` @ `2440d79`), which goes through `NSNumber`: the LOT-062 spec says why the exact text matters.

## Behaviour

All in `Sources/HFRModels/MPStorage/`, internal types.

1. **`JSONTokenizer.parse`** reads the text into a `JSONValue`, every number as a `JSONNumber` holding its lexeme.
   - RFC 8259, plus the two things Foundation's `JSONDecoder` also accepts, so a document it read still reads: a byte
     order mark before the value, and a trailing comma before `]` or `}`.
   - A repeated object key keeps its first value, as `JSONDecoder` does.
   - Nesting: 512 arrays or objects deep read, 513 refused, as `JSONDecoder` does. A deeper text throws instead of
     overflowing the stack.
   - A `\u` escape of an unpaired UTF-16 surrogate throws `MPStorageError.unpairedSurrogate(byteOffset:)` at the escape,
     in a key or a value. Any other malformed text throws `DecodingError.dataCorrupted`, as before.
2. **`JSONTreeDecoder`** decodes the models from that tree with `JSONDecoder`'s conversions:
   - a number decodes as an integer when its value is one (`1.0`, `1e2`), and as a floating-point value only when finite;
   - a string never decodes from a number, nor the reverse;
   - a missing key is `keyNotFound`, a wrong kind is `typeMismatch` with the coding path;
   - a `JSONValue` is taken whole (its `init(from:)` reads the decoder's value), so the unmodelled parts keep their lexemes.
3. **`JSONTreeEncoder`** builds the tree from the models: integers in decimal, a non-finite floating-point value refused,
   a value that encodes nothing written `{}` (refused at the top). A `JSONValue` is stored whole after checking that every
   number in it is valid JSON (`JSONNumber(Double.infinity)` is an `EncodingError`, as before).
4. **`JSONWriter.write`** writes the tree compactly, byte for byte what `JSONEncoder` writes with `.sortedKeys` and
   `.withoutEscapingSlashes`, numbers aside:
   - keys sorted by their UTF-8 bytes;
   - in strings: `"` and `\` escaped; `\b`, `\t`, `\n`, `\f`, `\r` for those controls; `\u00xx` (lowercase) for the other
     characters below U+0020; everything else as is (`/`, DEL, U+2028, U+2029, non-ASCII).
5. **`MPStorageCodec`**: `decode` is tokenizer then tree decoder; `encodeForWriting` and `validateWritable` are tree
   encoder then writer. The 64 KiB cap, the non-BMP guard and its JSON path, and the `noWritableEntry` check are
   unchanged.
6. **Lenient readers** (`MPStorageCoding.swift`): an integer, a string or a millisecond date written as a number or a
   string is read from the `JSONValue`, the number from its lexeme, with the rules the boxed path had:
   - an integer from its text, else from a whole value;
   - a string written as a number is its integer, else its `Double` description (`1.50` reads `1.5`), else its lexeme;
   - a date from the lexeme or the trimmed string, finite and in range.

`JSONNumberBox` is removed; no private-use marker is left. A plain `JSONEncoder`/`JSONDecoder` round trip of the
models still works through `Int64`/`Double`, as before.

## Parity with Foundation (probed on macOS 27, Swift 6.2)

- `JSONEncoder` (`.sortedKeys`, `.withoutEscapingSlashes`): key order by UTF-8 bytes (`A\u{30A}b` < `e\u{301}x` < `Å` <
  `éa` < U+FFFF < U+10000), and the escapes above. `JSONWriterTests` compare the writer with `JSONEncoder` on every
  control character, on those keys and on a nested document.
- `JSONDecoder`: trailing commas and a leading BOM accepted; `[1,,2]`, `[,1]`, `01`, `1.`, `.5`, `+1`, `NaN`,
  unquoted keys, comments and raw control characters refused; first duplicate key kept; 512 levels deep read, 513
  refused; `1.0` and `1e2` decode as `Int`. `JSONTokenizerTests` and `JSONTreeDecoderTests` check the same answers
  against `JSONDecoder` case by case, except depth: decoding a `JSONValue` 512 levels deep with `JSONDecoder` overflows a
  test thread's stack, so its limit was probed on the main thread.

## Edge cases

- A real string starting with U+E000 U+E001 followed by a number came back a number under LOT-062's boxing. It stays a
  string now.
- Unpaired surrogates: LOT-062 scanned the whole text for them before parsing, so a document with both a syntax error
  and a lone surrogate reported the surrogate. The tokenizer reports what it meets first.
- A document nested 512 levels deep decoded its unmodelled part through `JSONDecoder`'s recursive `JSONValue` decoding,
  which can overflow a small stack. The tree decoder takes a `JSONValue` whole, without recursion.

## Intentional differences from LOT-062

1. The marker string above stays a string.
2. Error precedence between a syntax error and a lone surrogate (above).

No legacy behaviour changes, so no CHANGELOG-LEGACY row.

## Tests

No capture needed: pure logic on a shared format, plus `R60a`'s stored document.

- Existing `MPStorageCodecTests`, `MPStorageDocumentTests`, `MPStorageMergeTests`, `MPStorageMutationTests` and
  `MPStoragePageParserTests`, unchanged and green.
- `MPStorageCodecTests`, new cases:
  - a string starting with the old marker stays a string (fails with LOT-062's boxing);
  - a modelled string written as a number reads from its lexeme (`1.50` → `1.5`, `7` → `7`).
- `MPStoragePageParserTests.writtenAsBefore`: `R60a`'s document is written back byte for byte as `JSONEncoder` wrote it.
- `JSONTokenizerTests`:
  - lexemes kept;
  - 39 grammar cases agree with `JSONDecoder`;
  - first duplicate kept;
  - escapes;
  - unpaired surrogates and their offsets;
  - depth.
- `JSONTreeDecoderTests`: 17 values × 10 types decode as with `JSONDecoder`; errors and coding paths.
- `JSONWriterTests`:
  - escapes, key order and a nested document equal `JSONEncoder`'s output;
  - lexemes are written as is;
  - a text round-trips;
  - the encoder's refusals.

Shown to fail with the behaviour removed (each mutation caught):
- trailing commas refused, last duplicate kept, BOM refused, wrong surrogate offset, no depth limit;
- keys sorted as Swift strings, uppercase hex, `/` escaped;
- `1.0` refused as an integer;
- `JSONValue` not read whole, or not written whole;
- the lenient string reader using the lexeme instead of the `Double` description.
