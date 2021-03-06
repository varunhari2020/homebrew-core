class Agda < Formula
  desc "Dependently typed functional programming language"
  homepage "https://wiki.portal.chalmers.se/agda/"
  license "BSD-3-Clause"
  revision 2

  stable do
    url "https://hackage.haskell.org/package/Agda-2.6.1.3/Agda-2.6.1.3.tar.gz"
    sha256 "bb1bc840cee95eea291bd220ea043b60153a6f7bd8198bc53be2bf3b83c8a1e7"

    resource "stdlib" do
      url "https://github.com/agda/agda-stdlib/archive/v1.6.tar.gz"
      sha256 "9dbfb6627d84cdb1db500d69a3ab2aad486e058e42c3ceddb8d9047fc74a84dc"
    end
  end

  bottle do
    sha256 big_sur:  "4b24fb91587c0678b749169522a0907bfd4553b50519c226e1ab6a71a055b882"
    sha256 catalina: "153d4d86e77ac143756932300264dc6fc60bb068d40d3e87cac1cffb27afa3c3"
    sha256 mojave:   "a87b626c89dbec0edac8cf130b8625d046ada5727a41145e012f667e336b960c"
  end

  head do
    url "https://github.com/agda/agda.git"

    resource "stdlib" do
      url "https://github.com/agda/agda-stdlib.git"
    end
  end

  depends_on "cabal-install"
  depends_on "emacs"
  depends_on "ghc" if MacOS.version >= :catalina

  uses_from_macos "zlib"

  on_macos { depends_on "ghc@8.8" if MacOS.version <= :mojave }
  on_linux { depends_on "ghc" }

  resource "alex" do
    url "https://hackage.haskell.org/package/alex-3.2.6/alex-3.2.6.tar.gz"
    sha256 "91aa08c1d3312125fbf4284815189299bbb0be34421ab963b1f2ae06eccc5410"
  end

  resource "cpphs" do
    url "https://hackage.haskell.org/package/cpphs-1.20.9.1/cpphs-1.20.9.1.tar.gz"
    sha256 "7f59b10bc3374004cee3c04fa4ee4a1b90d0dca84a3d0e436d5861a1aa3b919f"
  end

  resource "happy" do
    url "https://hackage.haskell.org/package/happy-1.20.0/happy-1.20.0.tar.gz"
    sha256 "3b1d3a8f93a2723b554d9f07b2cd136be1a7b2fcab1855b12b7aab5cbac8868c"
  end

  def install
    ENV["CABAL_DIR"] = prefix/"cabal"
    system "cabal", "v2-update"
    cabal_args = std_cabal_v2_args.reject { |s| s["installdir"] }

    # happy must be installed before alex
    %w[happy alex cpphs].each do |r|
      r_installdir = libexec/r/"bin"
      ENV.prepend_path "PATH", r_installdir

      resource(r).stage do
        mkdir r_installdir
        system "cabal", "v2-install", *cabal_args, "--installdir=#{r_installdir}"
      end
    end

    system "cabal", "v2-install", "-f", "cpphs", *std_cabal_v2_args

    # generate the standard library's documentation and vim highlighting files
    resource("stdlib").stage lib/"agda"
    cd lib/"agda" do
      system "cabal", "v2-install", *cabal_args, "--installdir=#{lib}/agda"
      system "./GenerateEverything"
      system bin/"agda", "-i", ".", "-i", "src", "--html", "--vim", "README.agda"
    end

    # Clean up references to Homebrew shims
    rm_rf "#{lib}/agda/dist-newstyle/cache"

    on_macos do
      bin.env_script_all_files libexec/"bin", PATH: "$PATH:#{Formula["ghc@8.8"].opt_bin}" if MacOS.version <= :mojave
    end
  end

  test do
    simpletest = testpath/"SimpleTest.agda"
    simpletest.write <<~EOS
      module SimpleTest where

      data ??? : Set where
        zero : ???
        suc  : ??? ??? ???

      infixl 6 _+_
      _+_ : ??? ??? ??? ??? ???
      zero  + n = n
      suc m + n = suc (m + n)

      infix 4 _???_
      data _???_ {A : Set} (x : A) : A ??? Set where
        refl : x ??? x

      cong : ??? {A B : Set} (f : A ??? B) {x y} ??? x ??? y ??? f x ??? f y
      cong f refl = refl

      +-assoc : ??? m n o ??? (m + n) + o ??? m + (n + o)
      +-assoc zero    _ _ = refl
      +-assoc (suc m) n o = cong suc (+-assoc m n o)
    EOS

    stdlibtest = testpath/"StdlibTest.agda"
    stdlibtest.write <<~EOS
      module StdlibTest where

      open import Data.Nat
      open import Relation.Binary.PropositionalEquality

      +-assoc : ??? m n o ??? (m + n) + o ??? m + (n + o)
      +-assoc zero    _ _ = refl
      +-assoc (suc m) n o = cong suc (+-assoc m n o)
    EOS

    iotest = testpath/"IOTest.agda"
    iotest.write <<~EOS
      module IOTest where

      open import Agda.Builtin.IO
      open import Agda.Builtin.Unit

      postulate
        return : ??? {A : Set} ??? A ??? IO A

      {-# COMPILE GHC return = \\_ -> return #-}

      main : _
      main = return tt
    EOS

    # we need a test-local copy of the stdlib as the test writes to
    # the stdlib directory
    resource("stdlib").stage testpath/"lib/agda"

    # typecheck a simple module
    system bin/"agda", simpletest

    # typecheck a module that uses the standard library
    system bin/"agda", "-i", testpath/"lib/agda/src", stdlibtest

    # compile a simple module using the JS backend
    system bin/"agda", "--js", simpletest

    # test the GHC backend
    cabal_args = std_cabal_v2_args.reject { |s| s["installdir"] }
    system "cabal", "v2-update"
    system "cabal", "v2-install", "ieee754", "--lib", *cabal_args

    # compile and run a simple program
    system bin/"agda", "-c", iotest
    assert_equal "", shell_output(testpath/"IOTest")
  end
end
