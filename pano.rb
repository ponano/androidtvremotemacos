cask "pano" do
  version "1.0.0"
  sha256 "607956f85a780a55ae0c87d4b8f748e96b212f46902981b635dba463ded51529"

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
