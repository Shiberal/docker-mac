class Nativestack < Formula
  desc "OrbStack-like macOS container manager built on Apple's container tool"
  homepage "https://github.com/nativestack/nativestack"
  license "Apache-2.0"
  version "0.2.0"

  # Prefer the monorepo checkout when this formula lives in Formula/nativestack.rb.
  # Falls back to the GitHub release tarball for remote tap installs.
  monorepo = File.expand_path("..", __dir__)
  if File.exist?(File.join(monorepo, "Package.swift"))
    url "file://#{monorepo}", using: :git, branch: "main"
  else
    # Stable release (update sha256 after tagging on GitHub):
    #   git archive --format=tar.gz --prefix=nativestack-0.2.0/ -o nativestack-0.2.0.tar.gz v0.2.0
    #   shasum -a 256 nativestack-0.2.0.tar.gz
    url "https://github.com/nativestack/nativestack/archive/refs/tags/v0.2.0.tar.gz"
    sha256 "630df8ac1ac573789b22e677bf46cd56923eef8f08e56d8f3f4cf067705092bd"
  end

  head "https://github.com/nativestack/nativestack.git", branch: "main"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sequoia
  depends_on arch: :arm64
  depends_on "container" => :recommended

  def install
    odie "NativeStack requires Apple Silicon (arm64)." unless Hardware::CPU.arm?

    ENV["MACOSX_DEPLOYMENT_TARGET"] = MacOS.version.to_s

    Dir.chdir(source_root) do
      system "swift", "build",
             "-c", "release",
             "--product", "nativestack",
             "-j", ENV.make_jobs
      bin.install ".build/release/nativestack"
    end
  end

  def caveats
    <<~EOS
      NativeStack wraps Apple's container tool. If the engine is not running yet:
        brew install container
        container system start

      Start the local API for the React Native GUI:
        nativestack serve

      Optional Docker / Compose compatibility (requires Homebrew):
        nativestack docker enable
        eval "$(nativestack docker env)"
    EOS
  end

  test do
    assert_match "OrbStack-like container manager", shell_output("#{bin}/nativestack --help")
  end

  private

  def source_root
    if tap&.path&.join("Package.swift")&.exist?
      tap.path
    else
      buildpath
    end
  end
end
