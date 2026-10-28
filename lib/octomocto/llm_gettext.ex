defmodule Octomocto.LlmGettext do
  @moduledoc """
  Translates the texts that admins write, such as notifications, with an
  LLM (see `Octomocto.Notifications.translate/1`). The translations are
  cached in the database.

  It has no `.po` files, so that a static text never goes to the LLM. The
  static texts use `OctomoctoWeb.Gettext`.
  """
  use Understudy.Backend,
    otp_app: :octomocto,
    priv: "priv/llm_gettext",
    repo: Octomocto.Repo,
    translator:
      {Understudy.Translator.ReqLLM,
       model: "google:gemini-3.1-flash-lite",
       llm_opts: [temperature: 0.5],
       persona:
         "You translate the announcements of Octomocto, a site with free online games to play solo or with friends.",
       style:
         "Informal and friendly. Always use the informal you (du, tu, ты, ти, ty, tu, tú, você).",
       rules: [
         ~s(Never translate "Octomocto".),
         "The text is Markdown on one line. Keep the Markdown syntax and the URLs of the links unchanged.",
         "In French, put a space before ! ? : and ;."
       ]}
end
