cask "pano" do
  version "1.0.0"
  sha256 "9d8c210750b221b709357cb757f6b2e367e95f228937772bf6f03374758b2c55"

  # Укажите здесь URL, куда вы загрузите созданный pano.zip
  # Например, GitHub Releases:
  url "https://github.com/ponano/androidtvremotemacos/releases/download/v#{version}/pano.zip"
  name "Pano"
  desc "macOS TV KVM client using Google TV Remote V2 protocol with smooth trackpad gestures and native voice input"
  homepage "https://github.com/ponano/androidtvremotemacos"

  app "Pano.app"

  zap trash: [
    "~/.tv_kvm_credentials",
    "~/Library/Logs/tv_kvm"
  ]
end
