cask "trading212-andon-cord" do
  version "0.2.0"
  # `Scripts/publish.sh` replaces this with the release archive's SHA-256
  # before creating the tag. The source cask is not published as-is.
  sha256 "bfdbfbcda0855afbb4d835a5c0ea9241db650ba43d1c193f5941e7fedf519cdf"

  url "https://github.com/marinsokol5/trading212-andon-cord/releases/download/v#{version}/Trading212-Andon-Cord-#{version}.zip"
  name "Trading212 Andon Cord"
  desc "Unofficial open-source Trading 212 portfolio menu bar and safety-first CLI"
  homepage "https://github.com/marinsokol5/trading212-andon-cord"

  depends_on macos: ">= :sonoma"

  app "Trading212 Andon Cord.app"
  binary "#{appdir}/Trading212 Andon Cord.app/Contents/Helpers/T212CLI.app/Contents/MacOS/t212"

  caveats <<~EOS
    Trading212 Andon Cord can place real market orders only from its `t212`
    command after you separately configure a trading key. Read the safety
    section in the README before configuring that key. The GUI has no
    order-placement code.
  EOS

  zap trash: [
    "~/Library/Preferences/com.marinsokol.trading212andoncord.plist",
  ]
end
