class OpensslUniversalAT11 < Formula
  desc "Cryptography and SSL/TLS Toolkit (universal library for macOS)"
  homepage "https://openssl.org/"
  url "https://www.openssl.org/source/openssl-1.1.1m.tar.gz"
  mirror "https://www.mirrorservice.org/sites/ftp.openssl.org/source/openssl-1.1.1m.tar.gz"
  mirror "http://www.mirrorservice.org/sites/ftp.openssl.org/source/openssl-1.1.1m.tar.gz"
  mirror "https://www.openssl.org/source/old/1.1.1/openssl-1.1.1m.tar.gz"
  mirror "https://www.mirrorservice.org/sites/ftp.openssl.org/source/old/1.1.1/openssl-1.1.1m.tar.gz"
  mirror "http://www.mirrorservice.org/sites/ftp.openssl.org/source/old/1.1.1/openssl-1.1.1m.tar.gz"
  sha256 "f89199be8b23ca45fc7cb9f1d8d3ee67312318286ad030f5316aca6462db6c96"
  license "OpenSSL"
  version_scheme 1

  livecheck do
    url "https://www.openssl.org/source/"
    regex(/href=.*?openssl[._-]v?(1\.1(?:\.\d+)+[a-z]?)\.t/i)
  end

  keg_only :shadowed_by_macos, "macOS provides LibreSSL"

  depends_on "ca-certificates"

  patch do
    url "https://raw.githubusercontent.com/nightuser/homebrew-universal-libraries/main/patches/openssl-universal%401.1/use_target.patch"
    sha256 "6ffb45e661595686dac1cb3b58e7f95ea7843078d2e2a0e7be0715f25d2d880f"
  end

  # SSLv2 died with 1.1.0, so no-ssl2 no longer required.
  # SSLv3 & zlib are off by default with 1.1.0 but this may not
  # be obvious to everyone, so explicitly state it for now to
  # help debug inevitable breakage.
  def configure_args
    %W[
      --prefix=#{prefix}
      --openssldir=#{openssldir}
      no-ssl3
      no-ssl3-method
      no-zlib
      enable-ec_nistp_64_gcc_128
    ]
  end

  def install
    # This could interfere with how we expect OpenSSL to build.
    ENV.delete("OPENSSL_LOCAL_CONFIG_DIR")

    # This ensures where Homebrew's Perl is needed the Cellar path isn't
    # hardcoded into OpenSSL's scripts, causing them to break every Perl update.
    # Whilst our env points to opt_bin, by default OpenSSL resolves the symlink.
    ENV["PERL"] = Formula["perl"].opt_bin/"perl" if which("perl") == Formula["perl"].opt_bin/"perl"

    current_arch = Hardware::CPU.arch
    other_arch = current_arch == "x86_64" ? "arm64" : "x86_64"

    for arch in [current_arch, other_arch] do
      build_dir = "build_#{arch}"
      mkdir_p build_dir
      chdir build_dir do
        system "perl", "../Configure", *(configure_args + %W[darwin64-#{arch}-cc])
        system "make"
      end
    end

    chdir "build_#{current_arch}" do
      libfiles = File.join("**", "*.{dylib,a}")
      Dir.glob(libfiles) do |lib|
        system "lipo", "-create", "-output", lib, "../build_#{other_arch}/#{lib}", lib
      end

      system "make", "install", "MANDIR=#{man}", "MANSUFFIX=ssl"
      # system "make", "test"
    end
  end

  def openssldir
    etc/"openssl@1.1"
  end

  def post_install
    rm_f openssldir/"cert.pem"
    openssldir.install_symlink Formula["ca-certificates"].pkgetc/"cert.pem"
  end

  def caveats
    <<~EOS
      A CA file has been bootstrapped using certificates from the system
      keychain. To add additional certificates, place .pem files in
        #{openssldir}/certs

      and run
        #{opt_bin}/c_rehash
    EOS
  end

  test do
    # Make sure the necessary .cnf file exists, otherwise OpenSSL gets moody.
    assert_predicate pkgetc/"openssl.cnf", :exist?,
            "OpenSSL requires the .cnf file for some functionality"

    # Check OpenSSL itself functions as expected.
    (testpath/"testfile.txt").write("This is a test file")
    expected_checksum = "e2d0fe1585a63ec6009c8016ff8dda8b17719a637405a4e23c0ff81339148249"
    system bin/"openssl", "dgst", "-sha256", "-out", "checksum.txt", "testfile.txt"
    open("checksum.txt") do |f|
      checksum = f.read(100).split("=").last.strip
      assert_equal checksum, expected_checksum
    end
  end
end
