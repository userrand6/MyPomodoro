class Mypomodoro < Formula
  desc "Lightweight macOS menu bar Pomodoro timer"
  homepage "https://github.com/OWNER/MyPomodoro"
  url "https://github.com/OWNER/MyPomodoro/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
  license "MIT"

  depends_on :macos

  def install
    system "make", "app"
    bin.install ".build/release/mypomodoro"
    prefix.install "dist/MyPomodoro.app"
  end

  service do
    run [opt_bin/"mypomodoro"]
    keep_alive successful_exit: false
    process_type :interactive
  end

  def caveats
    <<~EOS
      To launch MyPomodoro in your menu bar right now:
        mypomodoro &

      Or run it as a login/background service with Homebrew:
        brew services start mypomodoro

      You can also open or link the macOS app bundle:
        ln -sf "#{opt_prefix}/MyPomodoro.app" /Applications/MyPomodoro.app
        open "#{opt_prefix}/MyPomodoro.app"
    EOS
  end

  test do
    assert_predicate bin/"mypomodoro", :executable?
    assert_path_exists prefix/"MyPomodoro.app/Contents/MacOS/mypomodoro"
    assert_path_exists prefix/"MyPomodoro.app/Contents/Info.plist"
  end
end
