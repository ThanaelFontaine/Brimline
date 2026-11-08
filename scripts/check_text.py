r"""Repository text checks: no em or en dash, no personal data, no old product name in tracked text files,
and, in the workflows, GitHub-hosted runners only, pinned actions and pinned images.

The old name of the app (see OLD_NAME) may only appear where it is history or migration: the
files of OLD_NAME_FILES, and the lines that say "Formerly <old name>" (or the French
"Anciennement <old name>"). Anywhere else, in a text or in a file name, it is a problem.

The maintainer's own patterns (one regex per line, "#" comments) live outside the tracked
files: in .check-text.local at the repository root, and in ~/.config/check-text/patterns for
every repository of the machine. Without them (on the runners of GitHub, for one) only the generic
patterns run.

The repository is public: its workflows run on the runners hosted by GitHub, never on a machine of
the maintainer, whose code a pull request could run. Every file of .github/workflows (WORKFLOW_DIR)
goes through two checks, and each one alone fails the run:

A. A text check, line by line, with the YAML escapes \x, \u and \U decoded. It refuses every YAML
   form it cannot follow:
   - a line ending with "\", a quoted string still open at the end of the line, a flow mapping or
     sequence ("{", "[") not closed on the same line, an unclosed "${{" expression;
   - an explicit key "?", an anchor "&", an alias "*" or a tag "!" where a value starts, a
     document marker ("---", "...") or a "%" directive;
   - the word "self-hosted" anywhere, comments included;
   - one of the words runs-on, uses, image, container (any case) in a comment, or on a line that
     is not exactly one of the known forms: "runs-on: <label>" (plain value, one item list, or a
     block of one "- <label>" item), "uses: <target>", "image: <image>", "container: <image>",
     "container: {image: <image>}", or "container:" followed by a mapping;
   - a label outside the closed list HOSTED_LABELS (standard runners hosted by GitHub), an action
     not pinned by a full commit SHA of 40 lowercase hex characters (a local action "./..." is
     allowed; "docker://" images and reusable workflows of another repository are refused), an
     image of "container:" or "services:" without a "@sha256:" digest.
   The content of a block scalar ("run: |") is only searched for "self-hosted".

B. A structure check: the file is parsed by PyYAML (version pinned by hashes in
   scripts/requirements-check.txt), with duplicate keys and "<<" merge keys refused. Every job
   is checked: "runs-on" is one label of HOSTED_LABELS (a string, or a one item list), the "uses"
   of a job is a local workflow "./.github/workflows/...", every "steps[].uses" follows the rules
   of A, "container" (a string or a mapping with "image") and "services.*.image" carry a
   "@sha256:" digest, and no string of the file holds "self-hosted". A parse error, an
   unexpected type or a missing PyYAML fail the check (fail closed).

C. A check of the local actions: every "uses: ./<path>" of a workflow (and of the action files it
   reaches) must point to a folder holding a tracked action.yml or action.yaml. That file goes through
   A and B (every remote "uses" pinned by a full commit SHA, no unreadable form) and must be a
   composite action. A target that is missing, unreadable or outside the repository fails the run.

Usage: python3 scripts/check_text.py   (exit code 1 when something is found; PyYAML needed:
pip install --require-hashes --only-binary :all: -r scripts/requirements-check.txt)
"""
import posixpath
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # fail closed: check B reports it for every workflow
    yaml = None

EM_DASH = chr(0x2014)
EN_DASH = chr(0x2013)

GENERIC_PATTERNS = [
    re.compile(r"/Users/[A-Za-z]"),
    re.compile(r"/home/[a-z]"),
    re.compile(r"@gmail\.com"),
    re.compile(r"@icloud\.com"),
    re.compile(r"@outlook\."),
]

# Files allowed to quote the generic patterns (the checker and its test).
ALLOWED = {"scripts/check_text.py", "tests/test_check_text.py"}

# The app was called Sightglass until 26 October 2026 (QUOTA-34). Case does not matter.
OLD_NAME = re.compile("sightglass", re.IGNORECASE)
# A line that says where the name comes from is allowed anywhere.
OLD_NAME_LINE = re.compile("(formerly|anciennement) sightglass", re.IGNORECASE)
# Files where the old name is history (changelog, dated documents) or migration (the code that
# moves the old data, its tests, the installer that turns the old install off), and the checker.
OLD_NAME_FILES = {
    "CHANGELOG.md",
    "docs/releases/v0.1.0.md",
    "docs/releases/v0.2.0.md",
    "docs/audits/2026-10-26-securite.md",
    "Sources/BrimlineCore/LegacyMigration.swift",
    "tests/BrimlineCoreTests/LegacyMigrationTests.swift",
    "scripts/install.sh",
    "scripts/check_text.py",
    "tests/test_check_text.py",
}

# The workflows must run on the runners hosted by GitHub (see the top of this file).
WORKFLOW_DIR = ".github/workflows/"
SELF_HOSTED = re.compile("self-hosted", re.IGNORECASE)
# The labels of the standard runners hosted by GitHub: a closed list, copied from the tables of
# the official documentation (docs.github.com, Actions, "GitHub-hosted runners", read on
# 2026-11-08). A made-up label (macos-mini...) is refused; a new GitHub image is added here
# after reading that page.
HOSTED_LABELS = {
    "ubuntu-slim", "ubuntu-latest", "ubuntu-26.04", "ubuntu-24.04", "ubuntu-22.04",
    "ubuntu-26.04-arm", "ubuntu-24.04-arm", "ubuntu-22.04-arm",
    "windows-latest", "windows-2025", "windows-2025-vs2026", "windows-2022",
    "windows-11-arm", "windows-11-vs2026-arm",
    "macos-latest", "macos-26", "macos-15", "macos-26-intel", "macos-15-intel", "xcode-27",
}
_LEFT, _RIGHT = r"(?<![A-Za-z0-9_-])", r"(?![A-Za-z0-9_-])"
KEYWORD = re.compile(_LEFT + r"(runs-on|uses|image|container)" + _RIGHT, re.IGNORECASE)
KEYWORD_OR_SELF_HOSTED = re.compile(_LEFT + r"(runs-on|uses|image|container|self-hosted)" + _RIGHT, re.IGNORECASE)
RUNS_ON = re.compile(r"^(\s*)(?:-\s+)?runs-on:(?:\s+(.*))?$")
USES = re.compile(r"^\s*(?:-\s+)?uses:\s+(\S+)$")
IMAGE = re.compile(r"^\s*(?:-\s+)?image:\s+(\S+)$")
CONTAINER = re.compile(r"^(\s*)container:(?:\s+(\S+))?$")
CONTAINER_MAPPING = re.compile(r"^\s*container:\s+\{\s*image:\s+([^\s{},]+)\s*\}$")
ACTION = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_./-]+)?@([0-9a-f]{40})$")
ACTION_KEYS = {"name", "description", "author", "inputs", "outputs", "runs", "branding"}
LOCAL_WORKFLOW = re.compile(r"^\./\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$")
DIGEST = re.compile(r"@sha256:[0-9a-f]{64}$")
ESCAPE = re.compile(r"\\x([0-9A-Fa-f]{2})|\\u([0-9A-Fa-f]{4})|\\U([0-9A-Fa-f]{8})")
# Start of a block scalar: "key: |", "- key: >-", "- |" (a plain key, nothing else).
BLOCK = re.compile(r"^( *)((?:- +)*)([A-Za-z0-9_.-]+: +)?[|>][+-]?$")
# A YAML indicator (? & * !) where a value starts: start of line, after "- ", ": ", "? ", or
# after "[", "{", ",".
INDICATOR = re.compile(r"(?:^\s*(?:-\s+)*|:\s+|\?\s+|[\[{,]\s*)[?&*!]")
MAPPING_KEY = re.compile(r"^\s+[A-Za-z0-9_-]+:(\s|$)")
NOT_CHECKABLE = "workflow form not checkable"

BINARY_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif", ".ico", ".icns", ".heic",
    ".woff", ".woff2", ".ttf", ".otf", ".eot", ".pdf", ".zip", ".dmg",
}


def find_dashes(text):
    """Line numbers (1 based) containing an em dash or an en dash."""
    return [i + 1 for i, line in enumerate(text.split("\n")) if EM_DASH in line or EN_DASH in line]


def find_personal_data(path, text, patterns):
    """One "line N: reason" entry per line matching a pattern that is not allowed for this file."""
    if path in ALLOWED:
        return []
    hits = []
    for i, line in enumerate(text.split("\n")):
        for pattern in patterns:
            if pattern.search(line):
                hits.append(f"line {i + 1}: personal data pattern {pattern.pattern}")
    return hits


def find_old_name(path, text):
    """Line numbers (1 based) naming the old product, unless the file or the line is allowed to."""
    if path in OLD_NAME_FILES:
        return []
    return [i + 1 for i, line in enumerate(text.split("\n"))
            if OLD_NAME.search(line) and not OLD_NAME_LINE.search(line)]


def decode_escapes(line):
    """The line with the YAML escapes \\xNN, \\uNNNN and \\UNNNNNNNN decoded."""
    def one(match):
        try:
            return chr(int(match.group(1) or match.group(2) or match.group(3), 16))
        except ValueError:
            return match.group(0)
    return ESCAPE.sub(one, line)


def value_start(before):
    """True when a quote right after `before` opens a YAML string (and is not a character of a plain value)."""
    p = before.rstrip()
    return p == "" or p[-1] in "[{,:" or re.search(r"(?:^|\s)[-?]$", p) is not None


def scan(line):
    r"""Reads one line the way YAML would, without parsing it.

    Returns (code, comment, mask, open_reason): code is the line without its comment, mask is the
    code with the content of quoted strings and of ${{ }} expressions blanked, open_reason says
    what is left open at the end of the line (a string, an expression, a flow collection), or is
    None. In a double quoted string the character after "\" is skipped.
    """
    mask, i, n, depth, open_reason = [], 0, len(line), 0, None
    while i < n:
        c = line[i]
        if c == "#" and (i == 0 or line[i - 1] in " \t"):
            break
        if line.startswith("${{", i):
            end = line.find("}}", i + 3)
            if end < 0:
                open_reason = "${{ expression not closed on the line"
                mask.append(" " * (n - i))
                i = n
                break
            mask.append("$" + " " * (end + 1 - i))
            i = end + 2
            continue
        if c in "'\"" and value_start("".join(mask)):
            j = i + 1
            while j < n:
                if c == '"' and line[j] == "\\":
                    j += 2
                    continue
                if line[j] == c:
                    if c == "'" and j + 1 < n and line[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            if j >= n:
                open_reason = "quoted string not closed on the line"
                mask.append(c + " " * (n - i - 1))
                i = n
                break
            mask.append(c + " " * (j - i - 1) + c)
            i = j + 1
            continue
        if c in "[{":
            depth += 1
        elif c in "]}":
            depth -= 1
            if depth < 0:
                open_reason = open_reason or "closing bracket without an opening one"
        mask.append(c)
        i += 1
    if depth > 0 and not open_reason:
        open_reason = "flow mapping or sequence not closed on the line"
    return line[:i].rstrip(), line[i:], "".join(mask).rstrip(), open_reason


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        return value[1:-1]
    return value


def hosted_label(value):
    """True when value is one label of HOSTED_LABELS, plain, quoted or in a one item list."""
    if value.startswith("["):
        match = re.fullmatch(r"\[([^\[\]{},]*)\]", value)
        if not match:
            return False
        value = match.group(1)
    return unquote(value) in HOSTED_LABELS


def action_problem(target):
    """None when the target of a "uses" is a local action or an action pinned by a full commit SHA, else the problem."""
    if isinstance(target, str) and target.startswith("./"):
        return None
    if isinstance(target, str) and "/.github/workflows/" in target:
        return "reusable workflow of another repository"
    if isinstance(target, str) and ACTION.match(target):
        return None
    return "action not pinned by a full commit SHA"


def image_problem(image):
    if isinstance(image, str) and DIGEST.search(image):
        return None
    return "image not pinned by a sha256 digest"


def find_workflow_text_problems(path, text):
    """Check A: one "line N: problem" entry per problem of a file of the workflows folder."""
    if not path.startswith(WORKFLOW_DIR):
        return []
    return text_problems(text)


def text_problems(text):
    """Check A on a workflow text (also used on the action files a workflow reaches)."""
    problems = []
    lines = text.split("\n")
    block = None  # (column of the parent, indent of the content or None) inside a block scalar
    i = 0
    while i < len(lines):
        raw = lines[i]
        number = i + 1
        i += 1

        def problem(reason, number=number):
            problems.append(f"line {number}: {reason}")

        if SELF_HOSTED.search(decode_escapes(raw)):
            problem("self-hosted runner")
        if block is not None:
            if not raw.strip():
                continue
            indent = len(raw) - len(raw.lstrip(" "))
            parent, content = block
            if content is None and indent > parent:
                block = (parent, indent)
                continue
            if content is not None and indent >= content:
                continue
            block = None
        if not raw.strip():
            continue

        code, comment, mask, open_reason = scan(raw)
        if open_reason:
            problem(f"{NOT_CHECKABLE} ({open_reason})")
        if KEYWORD_OR_SELF_HOSTED.search(decode_escapes(comment)):
            problem(f"{NOT_CHECKABLE} (runs-on, uses, image, container or self-hosted in a comment)")
        if raw.rstrip().endswith("\\"):
            problem(f"{NOT_CHECKABLE} (line ending with a backslash)")
        if re.match(r"(---|\.\.\.|%)", raw):
            problem(f"{NOT_CHECKABLE} (YAML document marker or directive)")
        if INDICATOR.search(mask):
            problem(f"{NOT_CHECKABLE} (explicit key, anchor, alias or tag: ?, &, *, !)")
        match = BLOCK.match(code)
        if match:
            # Column of the parent: the key's, or the last "-" when there is no key.
            dashes = match.group(2) if match.group(3) else match.group(2).rstrip()[:-1]
            block = (len(match.group(1)) + len(dashes), None)

        if not KEYWORD.search(code) and not KEYWORD.search(decode_escapes(code)):
            continue
        match = CONTAINER_MAPPING.match(code)
        if match:
            reason = image_problem(unquote(match.group(1)))
            if reason:
                problem(reason)
            continue
        if "{" in code or "\\" in code:
            problem(f"{NOT_CHECKABLE} (flow style, JSON or escape)")
            continue
        match = RUNS_ON.match(code)
        if match:
            indent, value = match.group(1), (match.group(2) or "").strip()
            if not value:
                # Block form: exactly one "- label" item, indented deeper.
                items = []
                while i < len(lines):
                    following = scan(lines[i])[0]
                    if following.strip() and len(following) - len(following.lstrip()) <= len(indent):
                        break
                    if following.strip():
                        items.append(following.strip())
                    i += 1
                value = items[0][2:].strip() if len(items) == 1 and items[0].startswith("- ") else ""
            if not hosted_label(value):
                problem("runner not hosted by GitHub")
            continue
        match = USES.match(code)
        if match:
            reason = action_problem(unquote(match.group(1)))
            if reason:
                problem(reason)
            continue
        match = IMAGE.match(code)
        if match:
            reason = image_problem(unquote(match.group(1)))
            if reason:
                problem(reason)
            continue
        match = CONTAINER.match(code)
        if match:
            if match.group(2):
                reason = image_problem(unquote(match.group(2)))
                if reason:
                    problem(reason)
            else:
                # "container:" with no value: the next line must open a mapping, indented deeper.
                following = next((l for l in lines[i:] if l.strip()), "")
                if len(following) - len(following.lstrip(" ")) <= len(match.group(1)) or not MAPPING_KEY.match(following):
                    problem("image not pinned by a sha256 digest (container: with no image and no mapping)")
            continue
        problem(f"{NOT_CHECKABLE} (runs-on, uses, image or container in another form)")
    return problems


if yaml is not None:
    class StrictLoader(yaml.SafeLoader):
        """A SafeLoader that refuses duplicate keys and "<<" merge keys."""

    def _mapping(loader, node, deep=False):
        seen = set()
        for key, _ in node.value:
            if key.tag == "tag:yaml.org,2002:merge":
                raise yaml.constructor.ConstructorError(None, None, "merge key << refused", key.start_mark)
            value = loader.construct_object(key, deep=True)
            try:
                duplicate = value in seen
                seen.add(value)
            except TypeError:
                raise yaml.constructor.ConstructorError(None, None, "key that is not a scalar refused", key.start_mark)
            if duplicate:
                raise yaml.constructor.ConstructorError(None, None, f"duplicate key {value!r}", key.start_mark)
        return loader.construct_mapping(node, deep=deep)

    StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _mapping)


def strings(obj, seen=None):
    """Every string (key or value) of a loaded YAML document."""
    seen = set() if seen is None else seen
    if id(obj) in seen:
        return
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        seen.add(id(obj))
        for key, value in obj.items():
            yield from strings(key, seen)
            yield from strings(value, seen)
    elif isinstance(obj, list):
        seen.add(id(obj))
        for value in obj:
            yield from strings(value, seen)


def find_workflow_structure_problems(path, text):
    """Check B: one "<place>: problem" entry per problem of a file of the workflows folder, parsed by PyYAML."""
    if not path.startswith(WORKFLOW_DIR):
        return []
    if yaml is None:
        return ["PyYAML missing, the workflow cannot be parsed (fail closed): "
                "pip install --require-hashes --only-binary :all: -r scripts/requirements-check.txt"]
    doc, error = parse_yaml(text)
    if error:
        return [error]
    problems = []
    if any(SELF_HOSTED.search(s) for s in strings(doc)):
        problems.append("(file): self-hosted runner")
    if not isinstance(doc, dict):
        return problems + ["(file): the workflow is not a mapping"]
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        return problems + ["jobs: missing, empty or not a mapping"]
    for job_id, job in jobs.items():
        place = f"jobs.{job_id}"
        if not isinstance(job, dict):
            problems.append(f"{place}: the job is not a mapping")
            continue
        if "uses" in job and not (isinstance(job["uses"], str) and LOCAL_WORKFLOW.match(job["uses"])):
            problems.append(f"{place}.uses: reusable workflow of another repository")
        if "runs-on" in job or "uses" not in job:
            value = job.get("runs-on")
            if isinstance(value, list) and len(value) == 1:
                value = value[0]
            if "runs-on" not in job:
                problems.append(f"{place}.runs-on: missing (key written another way, or job with no runner)")
            elif not (isinstance(value, str) and value in HOSTED_LABELS):
                problems.append(f"{place}.runs-on: runner not hosted by GitHub")
        if "container" in job:
            container = job["container"]
            reason = image_problem(container.get("image") if isinstance(container, dict) else container)
            if reason:
                problems.append(f"{place}.container: {reason}")
        if "services" in job:
            services = job["services"]
            if not isinstance(services, dict):
                problems.append(f"{place}.services: not a mapping")
            else:
                for service_id, service in services.items():
                    reason = image_problem(service.get("image") if isinstance(service, dict) else service)
                    if reason:
                        problems.append(f"{place}.services.{service_id}: {reason}")
        if "steps" in job:
            problems += steps_problems(place, job["steps"])
    return problems


def steps_problems(place, steps):
    """One "<place>.steps[n]...: problem" entry per problem of a list of steps."""
    if not isinstance(steps, list):
        return [f"{place}.steps: not a list"]
    problems = []
    for rank, step in enumerate(steps):
        if not isinstance(step, dict):
            problems.append(f"{place}.steps[{rank}]: the step is not a mapping")
        elif "uses" in step:
            reason = action_problem(step["uses"])
            if reason:
                problems.append(f"{place}.steps[{rank}].uses: {reason}")
    return problems


def find_action_structure_problems(text):
    """Check B on the file of a local action: only a composite action is accepted, its steps follow the rules of the workflows."""
    if yaml is None:
        return ["PyYAML missing, the action cannot be parsed (fail closed): "
                "pip install --require-hashes --only-binary :all: -r scripts/requirements-check.txt"]
    doc, error = parse_yaml(text)
    if error:
        return [error]
    problems = []
    if any(SELF_HOSTED.search(s) for s in strings(doc)):
        problems.append("(file): self-hosted runner")
    if isinstance(doc, dict):
        for key in doc:
            if key not in ACTION_KEYS:
                problems.append(f"{key}: top-level key not allowed in an action file "
                                "(only name, description, author, inputs, outputs, runs, branding)")
    runs = doc.get("runs") if isinstance(doc, dict) else None
    if not isinstance(runs, dict):
        return problems + ["runs: missing or not a mapping (the action is not a mapping, or has no runs)"]
    if runs.get("using") != "composite":
        return problems + ["runs.using: only a composite action can be checked (not a JavaScript or Docker action)"]
    if "steps" not in runs:
        return problems + ["runs.steps: missing"]
    return problems + steps_problems("runs", runs["steps"])


def parse_yaml(text):
    """(document, None) or (None, the message of the refusal) with the strict loader."""
    try:
        return yaml.load(text, Loader=StrictLoader), None
    except (yaml.YAMLError, ValueError, TypeError, RecursionError) as error:
        first = str(error).strip().splitlines()[0] if str(error).strip() else type(error).__name__
        return None, f"YAML refused by the structure check: {first}"


def local_action_targets(text, kind="workflow"):
    """The "./<path>" targets of the steps of a workflow (jobs.*.steps) or of a composite action (runs.steps).
    The kind is given by the caller, never guessed from the keys: the runner ignores `jobs` in an action file."""
    if yaml is None:
        return []
    doc, error = parse_yaml(text)
    if error or not isinstance(doc, dict):
        return []
    lists = []
    if kind == "action":
        if isinstance(doc.get("runs"), dict):
            lists = [doc["runs"].get("steps")]
    elif isinstance(doc.get("jobs"), dict):
        lists = [job.get("steps") for job in doc["jobs"].values() if isinstance(job, dict)]
    return [step["uses"] for steps in lists if isinstance(steps, list) for step in steps
            if isinstance(step, dict) and isinstance(step.get("uses"), str) and step["uses"].startswith("./")]


def local_action_files(target, files):
    """(the tracked action.yml / action.yaml files of a "./<path>" target, the problem or None)."""
    if "${{" in target or "\\" in target:
        return [], f"uses {target}: local action path not checkable (expression or backslash)"
    folder = posixpath.normpath(target[2:] or ".")
    if folder == ".." or folder.startswith("../") or folder.startswith("/"):
        return [], f"uses {target}: local action outside the repository"
    found = [name for name in (posixpath.join(folder, "action.yml"), posixpath.join(folder, "action.yaml"))
             if name in files]
    if not found:
        return [], f"uses {target}: no action.yml or action.yaml tracked in {folder}"
    return found, None


def find_local_action_problems(path, text, files, read, checked=None, kind="workflow"):
    """Check C: every local action ("uses: ./<path>") of a file of the workflows folder must exist as a tracked
    action.yml or action.yaml, and that file passes the checks of the workflows (A and B), its own local
    actions included. `kind` is "workflow" for a workflow, "action" for an action file. Returns (file, "problem")
    pairs; `checked` keeps an action file from being read twice."""
    if not path.startswith(WORKFLOW_DIR):
        return []
    checked = set() if checked is None else checked
    problems = []
    for target in local_action_targets(text, kind):
        found, reason = local_action_files(target, files)
        if reason:
            problems.append((path, reason))
            continue
        for name in found:
            if name in checked:
                continue
            checked.add(name)
            try:
                content = read(name)
            except (OSError, UnicodeDecodeError) as error:
                problems.append((name, f"action file unreadable ({type(error).__name__})"))
                continue
            problems += [(name, hit) for hit in text_problems(content)]
            problems += [(name, hit) for hit in find_action_structure_problems(content)]
            problems += find_local_action_problems(WORKFLOW_DIR, content, files, read, checked, "action")
    return problems


def local_patterns(paths):
    """Patterns read from the files that exist among paths."""
    patterns = []
    for local in paths:
        if not local.is_file():
            continue
        lines = [l.strip() for l in local.read_text(encoding="utf-8").split("\n")]
        patterns += [re.compile(l) for l in lines if l and not l.startswith("#")]
    return patterns


def main():
    root = Path(__file__).resolve().parent.parent
    # -z: names with spaces or accents come back as they are, never quoted or split.
    listing = subprocess.run(["git", "ls-files", "-z"], cwd=root, capture_output=True, text=True, check=True).stdout
    files = [name for name in listing.split("\0") if name]
    patterns = GENERIC_PATTERNS + local_patterns([root / ".check-text.local", Path.home() / ".config/check-text/patterns"])
    tracked = set(files)
    checked = set()
    problems = []
    for name in files:
        path = root / name
        if OLD_NAME.search(name) and name not in OLD_NAME_FILES:
            problems.append(f"{name}: old product name in the file name")
        if path.suffix.lower() in BINARY_EXTENSIONS or not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        problems += [f"{name}: line {n}: em or en dash" for n in find_dashes(text)]
        problems += [f"{name}: line {n}: old product name" for n in find_old_name(name, text)]
        problems += [f"{name}: {hit}" for hit in find_workflow_text_problems(name, text)]
        problems += [f"{name}: {hit}" for hit in find_workflow_structure_problems(name, text)]
        problems += [f"{file}: {hit}" for file, hit in find_local_action_problems(
            name, text, tracked, lambda n: (root / n).read_text(encoding="utf-8"), checked)]
        problems += [f"{name}: {hit}" for hit in find_personal_data(name, text, patterns)]
    for p in problems:
        print(p)
    print(f"check_text: {len(files)} tracked files, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
