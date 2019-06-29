(define-module (packages)
  #:use-module (gnu packages base)
  #:use-module (gnu packages commencement)
  #:use-module (gnu packages cross-base)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages linux)
  #:use-module (guix build-system trivial)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix utils))

(define (make-ssp-fixed-gcc xgcc)
  (package (inherit xgcc)
           (source (origin (inherit (package-source xgcc))
                           (patches
                            (cons
                             (local-file "patches/gcc-i686-ssp.patch")
                             (origin-patches (package-source xgcc))))
                           (modules (origin-modules (package-source xgcc)))
                           (snippet
                            (origin-snippet (package-source xgcc)))))))

(define (make-gcc-rpath-link xgcc)
  (package
   (inherit xgcc)
   (arguments
    (substitute-keyword-arguments (package-arguments xgcc)
      ((#:phases phases)
       `(modify-phases ,phases
          (add-after 'pre-configure 'replace-rpath-with-rpath-link
            (lambda _
              (substitute* (cons "gcc/config/rs6000/sysv4.h"
                                 (find-files "gcc/config"
                                             "^gnu-user.*\\.h$"))
                (("-rpath=") "-rpath-link="))
              #t))))))))

(define bitcoin-gcc-9
  (make-gcc-rpath-link (make-ssp-fixed-gcc gcc-9)))

(define (cross-toolchain target
                         base-libc
                         base-kernel-headers
                         base-gcc-for-libc
                         base-gcc)
  "Create a cross-compilation toolchain package for TARGET"
  (let* ((xbinutils (cross-binutils target))
         ;; 1. Build a cross-compiling gcc without targeting any libc, derived
         ;; from BASE-GCC-FOR-LIBC
         (xgcc-sans-libc (cross-gcc target
                                    #:xgcc base-gcc-for-libc
                                    #:xbinutils xbinutils))
         ;; 2. Build cross-compiled kernel headers with XGCC-SANS-LIBC, derived
         ;; from BASE-KERNEL-HEADERS
         (xkernel (cross-kernel-headers target
                                        base-kernel-headers
                                        xgcc-sans-libc
                                        xbinutils))
         ;; 3. Build cross-compiled libc with XGCC-SANS-LIBC and XKERNEL,
         ;; derived from BASE-LIBC
         (xlibc (cross-libc target
                            base-libc
                            xgcc-sans-libc
                            xbinutils
                            xkernel))
         ;; 4. Build a cross-compiling gcc targeting XLIBC, derived from
         ;; BASE-GCC
         (xgcc (cross-gcc target
                          #:xgcc base-gcc
                          #:xbinutils xbinutils
                          #:libc xlibc)))
    ;; Define a meta-package that propagates the resulting XBINUTILS, XLIBC, and
    ;; XGCC
    (package
      (name (string-append target "-toolchain"))
      (version (package-version xgcc))
      (source #f)
      (build-system trivial-build-system)
      (arguments '(#:builder (begin (mkdir %output) #t)))
      (propagated-inputs
       `(("binutils" ,xbinutils)
         ("libc" ,xlibc)
         ("libc:static" ,xlibc "static")
         ("gcc" ,xgcc)))
      (synopsis (string-append "Complete GCC tool chain for " target))
      (description (string-append "This package provides a complete GCC tool
chain for " target " development."))
      (home-page (package-home-page xgcc))
      (license (package-license xgcc)))))

(define-public guix-native-toolchain
  (make-gcc-toolchain gcc-9 glibc-2.27))

(define-public xtoolchain-riscv64
  (cross-toolchain "riscv64-linux-gnu"
                   glibc-2.27
                   linux-libre-headers-4.19
                   gcc-8
                   bitcoin-gcc-9))

(define-public xtoolchain-x86_64
  (cross-toolchain "x86_64-linux-gnu"
                   glibc-2.27
                   linux-libre-headers-4.19
                   gcc
                   bitcoin-gcc-9))

(define-public xtoolchain-i686
  (cross-toolchain "i686-linux-gnu"
                   glibc-2.27
                   linux-libre-headers-4.19
                   gcc
                   bitcoin-gcc-9))

(define-public xtoolchain-aarch64
  (cross-toolchain "aarch64-linux-gnu"
                   glibc-2.27
                   linux-libre-headers-4.19
                   gcc
                   bitcoin-gcc-9))

(define-public xtoolchain-armhf
  (cross-toolchain "arm-linux-gnueabihf"
                   glibc-2.27
                   linux-libre-headers-4.19
                   gcc-6
                   bitcoin-gcc-9))
