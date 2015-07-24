require 'fileutils'
require 'mkmf'
require 'rbconfig'
$:.unshift File.expand_path('../../../lib', __FILE__)
require 'openbabel/version'

ob_num_ver = OpenBabel::VERSION
ob_ver     = "openbabel-"+ob_num_ver

RUBY=File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['ruby_install_name'])

main_dir = File.expand_path(File.join(File.dirname(__FILE__),"..",".."))
src_dir = File.join main_dir, ob_ver
build_dir = File.join main_dir, "build"
install_dir = main_dir 
install_lib_dir = File.join install_dir, "lib"
lib_dir = File.join main_dir, "lib", "openbabel"
ruby_src_dir = File.join src_dir, "scripts", "ruby"

begin
  nr_processors = `grep processor /proc/cpuinfo | wc -l` # speed up compilation, Linux only
rescue
  nr_processors = 1
end

begin
  Dir.chdir main_dir do
    FileUtils.rm_rf src_dir
    puts "Downloading OpenBabel sources"
    system "curl -L -d use_mirror=netcologne 'http://downloads.sourceforge.net/project/openbabel/openbabel/#{ob_num_ver}/openbabel-#{ob_num_ver}.tar.gz' | tar xz"
    system "sed -i -e 's/-Wl,-flat_namespace//;s/-flat_namespace//' #{File.join ruby_src_dir, "extconf.rb"}" # remove unrecognized compiler option
    system "sed -i -e 's/\\bConfig::CONFIG/RbConfig::CONFIG/' #{File.join ruby_src_dir, "extconf.rb"}" # Use RbConfig instread of Config
    system "sed -i -e 's/Init_OpenBabel/Init_openbabel/g' #{File.join ruby_src_dir,"*cpp"}" # fix swig bindings
    system "sed  -i -e 's/Config::CONFIG/RbConfig::CONFIG/' #{File.join src_dir, "scripts", "CMakeLists.txt" }" # fix Ruby Config
    system "sed  -i -e 's/Config::CONFIG/RbConfig::CONFIG/' #{File.join ruby_src_dir, "extconf.rb" }" # fix Ruby Config
  end
  FileUtils.mkdir_p build_dir
  FileUtils.mkdir_p install_dir
  Dir.chdir build_dir do
    puts "Configuring OpenBabel"
    cmake = "cmake #{src_dir} -DCMAKE_INSTALL_PREFIX=#{install_dir} -DBUILD_GUI=OFF -DENABLE_TESTS=OFF -DRUBY_BINDINGS=ON"
    # set rpath for local installations
    # http://www.cmake.org/Wiki/CMake_RPATH_handling
    # http://vtk.1045678.n5.nabble.com/How-to-force-cmake-not-to-remove-install-rpath-td5721193.html
    cmake += " -DCMAKE_INSTALL_RPATH:STRING=\"#{install_lib_dir}\"" unless have_library('openbabel')
    system cmake
  end
  unless have_library('openbabel')
    # local installation in gem directory
    Dir.chdir build_dir do
      puts "OpenBabel not installed. Compiling sources."
      system "make -j#{nr_processors}"
      system "make install"
      ENV["PKG_CONFIG_PATH"] = File.dirname(File.expand_path(Dir["#{install_dir}/**/openbabel*pc"].first))
    end
  end
  # compile ruby bindings
  puts "Compiling and installing OpenBabel Ruby bindings."
  Dir.chdir ruby_src_dir do
    # fix rpath
    system "sed -i 's|with_ldflags.*$|with_ldflags(\"#\$LDFLAGS -dynamic -Wl,-rpath,#{install_lib_dir}\") do|' #{File.join(ruby_src_dir,'extconf.rb')}" unless have_library('openbabel')
    # get include and lib from pkg-config
    ob_include=`pkg-config openbabel-2.0 --cflags-only-I`.sub(/\s+/,'').sub(/-I/,'')
    ob_lib=`pkg-config openbabel-2.0 --libs-only-L`.sub(/\s+/,'').sub(/-L/,'')
    system "#{RUBY} extconf.rb --with-openbabel-include=#{ob_include} --with-openbabel-lib=#{ob_lib}"
    system "make -j#{nr_processors}"
  end
  FileUtils.cp(ruby_src_dir+"/openbabel.#{RbConfig::CONFIG["DLEXT"]}", "./")
	File.open('Makefile', 'w') do |makefile|
		makefile.write <<"EOF"
.PHONY: openbabel.#{RbConfig::CONFIG["DLEXT"]}
openbabel.#{RbConfig::CONFIG["DLEXT"]}:
	chmod 755 openbabel.#{RbConfig::CONFIG["DLEXT"]}

.PHONY: install
install:
	mkdir -p #{lib_dir}
	mv openbabel.#{RbConfig::CONFIG["DLEXT"]} #{lib_dir}
EOF
  FileUtils.remove_entry_secure src_dir, build_dir
	end
ensure
  # Do NOT remove scr_dir and build_dir after build fails, they are necessary for debugging.
end
