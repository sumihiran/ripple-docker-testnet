FROM ubuntu:20.04 AS builder-base

ARG BOOST_VERSION=${BOOST_VERSION:-1.79.0}
ARG GCC_VERSION=${GCC_VERSION:-11}
ARG CLANG_VERSION=${CLANG_VERSION:-14}
ARG CMAKE_VERSION=${CMAKE_VERSION:-3.23.0}
ARG CARES_VERSION=${CARES_VERSION:-1.18.1}
ARG PROTOBUF_VERSION=${PROTOBUF_VERSION:-3.20.0}
ARG GRPC_VERSION=${GRPC_VERSION:-1.45.2}

ENV DEBIAN_FRONTEND noninteractive
ENV BOOST_VERSION=${BOOST_VERSION}

WORKDIR /opt/local/

RUN echo "Acquire::Retries 3;" > /etc/apt/apt.conf.d/80-retries && \
	echo "Acquire::http::Pipeline-Depth 0;" >> /etc/apt/apt.conf.d/80-retries && \
	echo "Acquire::http::No-Cache true;" >> /etc/apt/apt.conf.d/80-retries && \
	echo "Acquire::BrokenProxy    true;" >> /etc/apt/apt.conf.d/80-retries && \
	apt-get update -o Acquire::CompressionTypes::Order::=gz 

RUN apt-get -y update  && \
	apt-get -y upgrade  && \
	apt-get -y install apt-utils software-properties-common wget  && \
	add-apt-repository -y ppa:ubuntu-toolchain-r/test  && \
	apt-get -y clean  && \
	apt-get -y update &&\
	apt-get install --yes --no-install-recommends tzdata && \
	apt-get install --yes \
	lsb-release \
	# - for adding apt sources for Clang
	curl dpkg-dev apt-transport-https ca-certificates gnupg software-properties-common \
	# - Python headers for Boost.Python
	python-dev \
	# - for downloading rippled and submodules
	git \
	# - CMake generators (but not CMake itself)
	make ninja-build \
	# - compilers
	gcc-${GCC_VERSION} g++-${GCC_VERSION} \
	# protobuf dependencies
	libtool \
	# grpc dependencies
	zlib1g-dev \
	# - rippled dependencies
	libssl-dev pkg-config && \
	
	# Give us nice unversioned aliases for gcc and company.
	update-alternatives --install \
		/usr/bin/gcc gcc /usr/bin/gcc-${GCC_VERSION} 100 \
		--slave /usr/bin/g++ g++ /usr/bin/g++-${GCC_VERSION} \
		--slave /usr/bin/gcc-ar gcc-ar /usr/bin/gcc-ar-${GCC_VERSION} \
		--slave /usr/bin/gcc-nm gcc-nm /usr/bin/gcc-nm-${GCC_VERSION} \
		--slave /usr/bin/gcc-ranlib gcc-ranlib /usr/bin/gcc-ranlib-${GCC_VERSION} \
		--slave /usr/bin/gcov gcov /usr/bin/gcov-${GCC_VERSION} \
		--slave /usr/bin/gcov-tool gcov-tool /usr/bin/gcov-dump-${GCC_VERSION} \
		--slave /usr/bin/gcov-dump gcov-dump /usr/bin/gcov-tool-${GCC_VERSION} && \
	update-alternatives --auto gcc && \
	# The package `gcc` depends on the package `cpp`, but the alternative
	# `cpp` is a master alternative already, so it must be updated separately.
	update-alternatives --install \
		/usr/bin/cpp cpp /usr/bin/cpp-${GCC_VERSION} 100 && \
	update-alternatives --auto cpp && \

	export UBUNTU_CODENAME="$(lsb_release --short --codename)" && \

	# Add sources for Clang.
	curl --location https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - && \
	echo  "deb http://apt.llvm.org/${UBUNTU_CODENAME}/ llvm-toolchain-${UBUNTU_CODENAME}-${CLANG_VERSION} main\n\
deb-src http://apt.llvm.org/${UBUNTU_CODENAME}/ llvm-toolchain-${UBUNTU_CODENAME}-${CLANG_VERSION} main" >> /etc/apt/sources.list.d/llvm.list && \
	cat /etc/apt/sources.list.d/llvm.list && \
	apt-get update && \
	apt-get install --yes \
		# - clang, clang++, clang-tidy, clang-format
		clang-${CLANG_VERSION} clang-tidy-${CLANG_VERSION} clang-format-${CLANG_VERSION} \
		libclang-${CLANG_VERSION}-dev && \
	# Give us nice unversioned aliases for clang and company.
	update-alternatives --install \
		/usr/bin/clang clang /usr/bin/clang-${CLANG_VERSION} 100 \
		--slave /usr/bin/clang++ clang++ /usr/bin/clang++-${CLANG_VERSION} && \
	update-alternatives --auto clang  && \
	update-alternatives --install \
		/usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-${CLANG_VERSION} 100  && \
	update-alternatives --auto clang-tidy  && \
	update-alternatives --install \
		/usr/bin/clang-format clang-format /usr/bin/clang-format-${CLANG_VERSION} 100  && \
	update-alternatives --auto clang-format && \
	# Download and unpack CMake.
	cmake_slug="cmake-${CMAKE_VERSION}" && \
	curl --location --remote-name \
		"https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/${cmake_slug}.tar.gz" && \
	tar xzf ${cmake_slug}.tar.gz && \
	rm ${cmake_slug}.tar.gz && \
	# Build and install CMake.
	cd ${cmake_slug} && \
	./bootstrap --parallel=$(nproc) && \
	make -j $(nproc) && \
	make install && \
	cd .. && \
	rm --recursive --force ${cmake_slug} && \

	# Download and unpack protobuf.
	wget "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VERSION}/protobuf-all-${PROTOBUF_VERSION}.tar.gz" && \
	tar xf protobuf-all-${PROTOBUF_VERSION}.tar.gz && \
	cd protobuf-${PROTOBUF_VERSION} && \
	./autogen.sh && \
	./configure && \
	make -j$(nproc) && \
	make install && \
	ldconfig && \
	cd .. && \
	rm -f protobuf-all-${PROTOBUF_VERSION}.tar.gz && \
	rm -rf protobuf-${PROTOBUF_VERSION} && \

	# Download and unpack c-ares 
	wget https://c-ares.haxx.se/download/c-ares-${CARES_VERSION}.tar.gz  && \
	tar xf c-ares-${CARES_VERSION}.tar.gz  && \
	cd c-ares-${CARES_VERSION} && \
	mkdir build && \
	cd build  && \
	cmake \
		-DHAVE_LIBNSL=OFF \
		-DCMAKE_BUILD_TYPE=Release \
		-DCARES_STATIC=ON \
		-DCARES_SHARED=OFF \
		-DCARES_INSTALL=ON \
		-DCARES_STATIC_PIC=ON \
		-DCARES_BUILD_TOOLS=OFF \
		-DCARES_BUILD_TESTS=OFF \
		-DCARES_BUILD_CONTAINER_TESTS=OFF \
		..  && \
	make -j$(nproc)  && \
	make install  && \
	cd ../..  && \
	rm -f c-ares-${CARES_VERSION}.tar.gz  && \
	rm -rf c-ares-${CARES_VERSION} && \

	# Download and unpack and install grpc.
	git clone -b v${GRPC_VERSION} https://github.com/grpc/grpc && \
	cd grpc && \
	git submodule update --init && \
	mkdir _bld && cd _bld && \
	cmake \ 
		-DCMAKE_BUILD_TYPE=Release \ 
		-DBUILD_SHARED_LIBS=OFF \ 
		-DgRPC_ZLIB_PROVIDER=package \ 
		-DgRPC_CARES_PROVIDER=package \ 
		-DgRPC_SSL_PROVIDER=package \ 
		-DgRPC_PROTOBUF_PROVIDER=package \ 
		-DProtobuf_USE_STATIC_LIBS=ON \
		-DgRPC_ABSL_PROVIDER=module \
		.. && \
	make -j$(nproc) && \
	make install && \
	cd ../.. && \
	rm -rf grpc && \

	# Download and unpack Boost.
	boost_slug="boost_$(echo ${BOOST_VERSION} | tr . _)" && \
	curl --location --remote-name \
		"https://boostorg.jfrog.io/artifactory/main/release/${BOOST_VERSION}/source/${boost_slug}.tar.gz" && \
	tar xzf ${boost_slug}.tar.gz && \
	rm ${boost_slug}.tar.gz && \

	# Build and install Boost.
	cd ${boost_slug} && \
	./bootstrap.sh && \
	./b2 \
		--with-chrono \
		--with-container \
		--with-context \
		--with-coroutine \
		--with-date_time \
		--with-filesystem \
		--with-program_options \
		--with-regex \
		--with-system \
		--with-atomic \
		--with-thread \
		link=static -j $(nproc)

FROM builder-base as builder

ARG RIPPLED_VERSION=${RIPPLED_VERSION:-1.9.0}

RUN git clone --single-branch -b $RIPPLED_VERSION  https://github.com/ripple/rippled.git && \
	cd rippled && \
	mkdir build && cd build && \
	boost_slug="boost_$(echo ${BOOST_VERSION} | tr . _)" && \
	cmake -Dstatic=ON -DBOOST_ROOT=/opt/local/${boost_slug} -DBOOST_ROOT=/opt/local/${boost_slug}/lib ..

RUN cd /root/rippled/build && \
  cmake --build . -- -j $(nproc)

FROM ubuntu:20.04

LABEL maintainer="ns@sumihiran.me"

COPY --from=builder /root/rippled/build/rippled /usr/local/bin/rippled

