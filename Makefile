V             ?= 0
CONFIGURATION = Debug
MSBUILD       = xbuild /p:Configuration=$(CONFIGURATION) $(MSBUILD_ARGS)

ifneq ($(V),0)
MONO_OPTIONS += --debug
MSBUILD      += /v:d
endif

ifneq ($(MONO_OPTIONS),)
export MONO_OPTIONS
endif

all:
	$(MSBUILD)

prepare:
	git submodule update --init --recursive
	nuget restore
	(cd external/Java.Interop && nuget restore)

clean:
	$(MSBUILD) /t:Clean

git-reset: git-reset-submodules
	git clean -xdf
	git reset --hard

git-reset-submodules:
	(cd external/mono && git reset --hard && git clean -xdf)
	(cd external/Java.Interop && git reset --hard && git clean -xdf)

git-update-submodules: git-reset-submodules
	git submodule update --init --recursive
	nuget restore
	(cd external/Java.Interop && git pull origin master && nuget restore)

fix-linux-pre-build:
	cat Configuration.Override.props.in \
		| sed 's@clang<@clang-3.8<@gm' \
		| sed 's@clang++<@clang++-3.8<@gm' \
		> Configuration.Override.props
	sed -i 's@= Release.AnyCPU@= Release|Any CPU@gm' Xamarin.Android.sln
	sed -i 's@LINUX_JAVA_INCLUDE_DIRS          = /usr/lib/jvm/default-java/include/@LINUX_JAVA_INCLUDE_DIRS          = /usr/lib/jvm/default-java/include@gm' external/Java.Interop/build-tools/scripts/jdk.mk
	sed -i 's@LINUX_JAVA_JNI_OS_INCLUDE_DIR    = ..DESKTOP_JAVA_JNI_INCLUDE_DIR./linux@LINUX_JAVA_JNI_OS_INCLUDE_DIR    = $(DESKTOP_JAVA_JNI_INCLUDE_DIR)/include/linux@gm' external/Java.Interop/build-tools/scripts/jdk.mk
	sed -i 's@rm src/Java.Runtime.Environment/Java.Runtime.Environment.dll.config@rm -f src/Java.Runtime.Environment/Java.Runtime.Environment.dll.config@gm' external/Java.Interop/Makefile

fix-linux-post-build:
	# copy targets to output
	cp ./src/Xamarin.Android.Build.Tasks/*.targets bin/$(CONFIGURATION)/lib/xbuild/Xamarin/Android/

	# Replace Ionic.Zip by another version!
	#
	#   An "Path is empty" exception message is triggered by that DotNetZip tries to pass "" to Directory.Create() in ZipEntry.Extract, line 760.
	#   The cause is that the variable targetFileName contain the path using "\" as directory separator. When run on linux the path is interpreted as a single filename making the directory path "".
	#     - outFileName = outFileName.Replace("/","\");
	#     + outFileName = outFileName.Replace('/', Path.DirectorySeparatorChar);
	( \
		rm -r tmp-DotNetZip \
		mkdir tmp-DotNetZip \
		cd tmp-DotNetZip && ( \
			wget -O DotNetZip.zip https://www.nuget.org/api/v2/package/DotNetZip/1.9.8 \
			unzip DotNetZip.zip \
			cp lib/net20/Ionic.Zip.dll bin/$(CONFIGURATION)/lib/mandroid/
			cp lib/net20/Ionic.Zip.dll bin/$(CONFIGURATION)/lib/xbuild/Xamarin/Android/Ionic.Zip.dll
		) \
	)


java-interop:
	(cd external/Java.Interop && nuget restore && make all)
	mkdir -p bin/$(CONFIGURATION)/bin
	mkdir -p bin/$(CONFIGURATION)/lib/mandroid
	rsync -av external/Java.Interop/bin/$(CONFIGURATION)/ bin/$(CONFIGURATION)/lib/mandroid/
	( \
		echo '#!/bin/bash' \
		echo 'DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"' \
		echo '' \
	) > bin/$(CONFIGURATION)/bin/generator
	chmod +x bin/$(CONFIGURATION)/bin/generator

all-linux: fix-linux-pre-build java-interop all fix-linux-post-build

all-debian: build-dep-debian all-linux

build-dep-debian:
	# cleanup
	sudo rm -f /etc/apt/sources.list.d/llvm.list
	# mono 4.4
	sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
	(echo "deb http://download.mono-project.com/repo/debian wheezy main"; echo "deb-src http://download.mono-project.com/repo/debian wheezy main") | sudo tee /etc/apt/sources.list.d/mono-xamarin.list
	(echo "deb http://download.mono-project.com/repo/debian beta main";echo "deb-src http://download.mono-project.com/repo/debian beta main") | sudo tee /etc/apt/sources.list.d/mono-xamarin-beta.list
	sudo apt update
	sudo apt install mono-devel referenceassemblies-pcl
	sudo apt-get build-dep mono
	# llvm 3.8
	echo '(grep UBUNTU_CODENAME /etc/os-release || dpkg --status tzdata|grep Provides | sed 's@-@=@') | cut -f2 -d=' > .codename.sh
	$(eval CODENAME := $(shell bash .codename.sh))
	(echo "deb http://llvm.org/apt/$(CODENAME)/ llvm-toolchain-$(CODENAME)-3.8 main";echo "deb-src http://llvm.org/apt/$(CODENAME)/ llvm-toolchain-$(CODENAME)-3.8 main") | sudo tee /etc/apt/sources.list.d/llvm.list
	wget -O - http://llvm.org/apt/llvm-snapshot.gpg.key|sudo apt-key add -
	sudo apt update
	sudo apt install clang-3.8
	# 32 bit libraries for android toolchain
	sudo dpkg --add-architecture i386
	sudo apt install zlib1g:i386

