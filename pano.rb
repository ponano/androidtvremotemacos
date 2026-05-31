cask "pano" do
  version "1.0.0"
  sha256 "2579c003f1233d69a5c73e729aed55082c0b910631bf40c70b14309c5add5d7f"

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
