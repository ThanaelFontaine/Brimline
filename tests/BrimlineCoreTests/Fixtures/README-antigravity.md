The `antigravity-usage-*.txt` files are test data for `agy --print /usage`.

`antigravity-usage-normal.txt` has the form of the real text, seen on Antigravity CLI 1.4.8 on the Mac mini on
27/10/2026 (`agy --print /usage --sandbox`, a free Google account): no header line, four columns separated by tabs
(group, name of the limit, percentage remaining, reset time in ISO 8601), two windows (`Five Hour`, `Weekly`), a group
of other vendors' models (`Claude and GPT models`) and a limit of one model (`Gemini 4 Argon Weekly Limit`). The
percentages and the dates are replaced (the real text said 100 % everywhere); the names are the real ones. Antigravity
CLI 1.4.9, tried the same way on 28/10/2026, printed exactly that form (the same five lines, names, tabs and columns):
Antigravity CLI 1.4.10, tried the same way on 29/10/2026, printed that form again (five lines, same names, tabs and columns). The file stands for the three builds.

The other files are broken variants, each with one defect: a line of a model's sentence in a name (`-model-line`), a valid line followed by a sentence of the old guessed form (`-hostile`), three columns instead of
four, a percentage out of bounds, an empty text.
