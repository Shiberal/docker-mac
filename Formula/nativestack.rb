class Nativestack < Formula
  desc "OrbStack-like macOS container manager built on Apple's container tool"
  homepage "https://github.com/nativestack/nativestack"
  license "Apache-2.0"
  version "0.2.0"

  # Monorepo tap: build from the tap checkout via local git.
  # Remote tap: falls back to the GitHub release tarball.
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

  # Fetched before the sandboxed build phase (SPM cannot download deps during install).
  resource "swift-argument-parser" do
    url "https://github.com/apple/swift-argument-parser.git",
        tag: "1.8.2",
        revision: "6a52f3251125d74daf04fcbd5e6f08a75d074382"
  end

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sequoia
  depends_on arch: :arm64
  depends_on "container" => :recommended

  def install
    odie "NativeStack requires Apple Silicon (arm64)." unless Hardware::CPU.arm?

    ENV["MACOSX_DEPLOYMENT_TARGET"] = "27"
    dep = resource("swift-argument-parser")

    cd project_root do
      Pathname(".build").rmtree if Pathname(".build").exist?

      checkout = Pathname(".build/checkouts/swift-argument-parser")
      checkout.parent.mkpath
      dep.stage checkout

      system "swift", "build",
             "-c", "release",
             "--disable-sandbox",
             "--product", "nativestack"
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

  # Always build inside Homebrew's buildpath — never in the tap checkout.
  def project_root
    return buildpath if (buildpath/"Package.swift").exist?

    # GitHub archive tarballs extract into nativestack-<version>/.
    candidates = buildpath.children.select { |path| (path/"Package.swift").exist? }
    odie "Could not find Package.swift under #{buildpath}" if candidates.empty?

    candidates.first
  end
end
