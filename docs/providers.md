# Providers

What Brimline reads for each provider, where the source comes from, and what it says when there is nothing it can read. Claude is on by default; every other provider is **off until you turn it on** (Settings, Accounts, or `brimline providers enable <name>`).

**Documented** means described by the provider's official documentation (with a link). **Not documented** means seen in the code of the provider's own client: it can change without notice.

## Claude

Read from the Claude Code sign-in in the macOS Keychain, with one request to `https://api.anthropic.com/api/oauth/usage` (not documented by Anthropic). See [Linking your accounts](accounts.md) and [SECURITY.md](../SECURITY.md).

## Gemini: a sentence only

- **What Brimline does.** It looks only for the folder `~/.gemini` (Gemini CLI's folder) and checks that it exists and is a folder. When it does, Gemini shows one card with the sentence below. Nothing inside the folder is opened or listed, nothing is read from the Keychain, no request is made and no program is launched. When Gemini is off (the default), the folder is not even looked for.
- **Why nothing is read.** Google publishes no limit of a Gemini subscription in a form an app like Brimline can read. The call Gemini CLI itself makes (`v1internal:retrieveUserQuota`, not documented) appears, as far as Gemini CLI's code shows, to serve only Code Assist Standard and Enterprise, and since 18 June 2026 "Login with Google" in Gemini CLI is no longer possible for individual, Google AI Pro and Google AI Ultra plans ([Google's notice](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals)). The Gemini app shows its own limits, which repeat every 5 hours up to a weekly limit ([Google's help page](https://support.google.com/gemini/answer/16275805)); the only known way to read them from outside is with browser cookies, which Brimline never reads.
- **The sentence** (`not_readable`, reason `consumer_plan`, in the app, in `brimline status` and in the JSON for agents):
  - English: "Google does not publish Gemini limits in a form Brimline can read. They are in the Gemini app (Settings, Usage limits) and in Gemini CLI (/stats model)."
  - French: "Google ne publie pas les limites de Gemini sous une forme que Brimline peut lire. Elles sont dans l'app Gemini (Réglages, Limites d'utilisation) et dans Gemini CLI (/stats model)."
- **What you see.** No percentage and no reset time, never an invented number. The account is never offered by `best_account`.
- **Checked** on 27 October 2026 against the sources linked above.
