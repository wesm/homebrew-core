class Llgo < Formula
  desc "Go compiler based on LLVM integrate with the C ecosystem and Python"
  homepage "https://github.com/xgo-dev/llgo"
  license "Apache-2.0"
  head "https://github.com/xgo-dev/llgo.git", branch: "main"

  stable do
    url "https://github.com/xgo-dev/llgo/archive/refs/tags/v0.13.0.tar.gz"
    sha256 "4b413886ba07f37ce7d6b4cd088e98e2d0bddfdc1a68f33cdd7b027bffcb6990"

    # Backport plan9asm update to fix Go 1.25+ on arm64
    patch do
      url "https://github.com/xgo-dev/llgo/commit/76a913ff126cc91d500e223d84661b20e8bc4e75.patch?full_index=1"
      sha256 "747bd47539a6900de4391f3a7e9246e58af67be32fab5358b6f7d6ff54219355"
      type :backport
    end
    patch do
      url "https://github.com/xgo-dev/llgo/commit/4a1c8967ff09a528ae80529c4e05b359455dd467.patch?full_index=1"
      sha256 "0db29e139fd3cd4d7304d3b20b58fc483317ea93ae9f7e81ec20156bd6565010"
      type :backport
    end
    patch do
      url "https://github.com/xgo-dev/llgo/commit/b1cf3f532eb4b3629d3612e2e629334926744034.patch?full_index=1"
      sha256 "a0df2aedf39d9a63a76e2805670f0e7e388322fbf9b3edc9e89b231027120560"
      type :backport
    end
    patch do
      url "https://github.com/xgo-dev/llgo/commit/81726f17b7d5e54bc499de028b7dc1883f0182e3.patch?full_index=1"
      sha256 "a8e9f93a119c3553c7c4bac1d7d77eefc495a80670a6efdb2d75b6965ac9a7d4"
      type :backport
    end
    patch do
      url "https://github.com/xgo-dev/llgo/commit/5f0475cc7eac8389c48121016736a787683eb9cc.patch?full_index=1"
      sha256 "ca9d00ab8bfb6b436ca61966e7f2d979a2fea8fc94f678d747af342035f8eeb8"
      type :backport
    end
  end

  livecheck do
    url :stable
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  bottle do
    sha256 cellar: :any, arm64_tahoe:   "478656cf92824d87b7ba41a8d166eb01c523019c17e03b35d00daedd826e277a"
    sha256 cellar: :any, arm64_sequoia: "cc685e59d51a44981a1747225c3f1c3f4ecb5c991670b1ca94c9bd6395b87cb1"
    sha256 cellar: :any, arm64_sonoma:  "754249171424bc00731d137b6c0528c3405df704535bc128e4c86ddeaf4be14d"
    sha256 cellar: :any, sonoma:        "e67804fb00af76fc2e147a801b2174ff89083008f401de1af3acc006d2c66c86"
    sha256               arm64_linux:   "d805ea8a6ec80bc309013a6860062c4e584a973cd876a9a289f408407e3633f0"
    sha256               x86_64_linux:  "5aae678328b29b9217d6952fa1d8d4c0e23f51c63b3a6556fe3052c70e8d965e"
  end

  depends_on "bdw-gc" => :no_linkage
  depends_on "go@1.25"
  depends_on "libuv" => :no_linkage
  depends_on "openssl@3"
  depends_on "pkgconf"

  uses_from_macos "libffi"

  on_macos do
    depends_on "lld@21"
    depends_on "llvm@21"
  end

  on_linux do
    depends_on "libunwind"
    depends_on "lld@19"
    depends_on "llvm@19"
    depends_on "zlib-ng-compat"
  end

  def find_dep(name)
    deps.find { |f| f.name.match?(/^#{name}(@\d+(\.\d+)*)?$/) }
        .to_formula
  end

  def install
    llvm = find_dep("llvm")
    ldflags = %W[
      -X github.com/goplus/llgo/internal/env.buildVersion=v#{version}
      -X github.com/goplus/llgo/internal/env.buildTime=#{time.iso8601}
      -X github.com/goplus/llgo/xtool/env/llvm.ldLLVMConfigBin=#{llvm.opt_bin}/llvm-config
    ]
    tags = %W[llvm#{llvm.version.major}]
    path_deps = %w[lld go pkgconf].map { |name| find_dep(name).opt_bin }
    path_deps << llvm.opt_bin
    script_env = { PATH: "#{path_deps.join(":")}:${PATH}" }

    if OS.linux?
      # Workaround to avoid patchelf corruption when cgo is required
      if Hardware::CPU.arm64?
        ENV["CGO_ENABLED"] = "1"
        ENV["GO_EXTLINK_ENABLED"] = "1"
        ENV.append "GOFLAGS", "-buildmode=pie"
      end

      ENV.prepend "CGO_CPPFLAGS",
        "-I#{llvm.opt_include} " \
        "-D_GNU_SOURCE " \
        "-D__STDC_CONSTANT_MACROS " \
        "-D__STDC_FORMAT_MACROS " \
        "-D__STDC_LIMIT_MACROS"
      ENV.prepend "CGO_LDFLAGS", "-L#{llvm.opt_lib} -lLLVM"

      tags << "byollvm"
      libunwind = find_dep("libunwind")
      script_env[:CFLAGS] = "-I#{libunwind.opt_include} ${CFLAGS}"
      script_env[:LDFLAGS] = "-L#{libunwind.opt_lib} -Wl,-rpath,#{libunwind.opt_lib} ${LDFLAGS}"
    end

    system "go", "build", *std_go_args(ldflags:, tags:), "./cmd/llgo"
    bin.env_script_all_files(libexec/"bin", script_env)
    libexec.install "LICENSE", "README.md", "go.mod", "go.sum", "runtime"
  end

  test do
    go = find_dep("go")
    goos = shell_output("#{go.opt_bin}/go env GOOS").chomp
    goarch = shell_output("#{go.opt_bin}/go env GOARCH").chomp
    assert_equal "llgo v#{version} #{goos}/#{goarch}", shell_output("#{bin}/llgo version").chomp

    # Add bdw-gc library path to LD_LIBRARY_PATH, this is a workaround for the libgc.so not found issue
    # Will be fixed in the next release
    bdwgc = find_dep("bdw-gc")
    ENV.prepend_path "LD_LIBRARY_PATH", bdwgc.opt_lib

    (testpath/"hello.go").write <<~'GO'
      package main

      import (
          "fmt"

          "github.com/goplus/lib/c"
      )

      func Foo() string {
        return "Hello LLGo by Foo"
      }

      func main() {
        fmt.Println("Hello LLGo by fmt.Println")
        c.Printf(c.Str("Hello LLGo by c.Printf\n"))
      }
    GO
    (testpath/"hello_test.go").write <<~GO
      package main

      import "testing"

      func Test_Foo(t *testing.T) {
        got := Foo()
        want := "Hello LLGo by Foo"
        if got != want {
          t.Errorf("foo() = %q, want %q", got, want)
        }
      }
    GO
    (testpath/"go.mod").write <<~GOMOD
      module hello
    GOMOD

    expected = "Hello LLGo by fmt.Println\nHello LLGo by c.Printf\n"
    system go.opt_bin/"go", "get", "github.com/goplus/lib"
    # Test llgo run
    assert_equal expected, shell_output("#{bin}/llgo run .")
    # Test llgo build
    system bin/"llgo", "build", "-o", "hello", "."
    assert_equal expected, shell_output("./hello")
    # Test llgo test
    assert_match "PASS", shell_output("#{bin}/llgo test .")
  end
end
