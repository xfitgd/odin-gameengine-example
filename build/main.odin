package main

import "core:fmt"
import "core:encoding/json"
import "core:mem"
import "core:slice"
import "core:os"
import "core:os/os2"
import "core:strings"
import "core:sys/linux"
import "core:path/filepath"


read_build_json :: proc() -> (json.Value, bool) {
	f, ok := os.read_entire_file("build.json")
	if(!ok) {
		fmt.eprintln("err: not found build.json!")
		return nil, false
	}
	//fmt.println(string(f))
	defer delete(f)

	json_data, json_err  := json.parse(f)
	if(json_err != .None) {
		fmt.eprintln("err: json ", json_err)
		return nil, false
	}
	return json_data, true
}

/*
arm-linux-gnueabi
aarch64-linux-gnu
i686-linux-gnu
x86_64-linux-gnu
riscv64-linux-gnu
*/

main :: proc() {
	//fmt.println(os.args)
	json_data:json.Value
	ok :bool

	if len(os.args) > 1 && os.args[1] == "install" {
	} else if len(os.args) > 1 && os.args[1] == "clean" {
		if json_data, ok = read_build_json() ; !ok {return}
		defer json.destroy_value(json_data)
		setting := (json_data.(json.Object)["setting"]).(json.Object)

		os.remove(setting["out-path"].(json.String))
	} else {
		if json_data, ok = read_build_json() ; !ok {return}
		defer json.destroy_value(json_data)
		//fmt.println(json_data)
	
		setting := (json_data.(json.Object)["setting"]).(json.Object)
	
		is_android := setting["is-android"].(json.Boolean);
		out_path := strings.join({"-out:", setting["out-path"].(json.String)}, "")
		defer delete(out_path)

		// Sets the optimization mode for compilation.
		// Available options:
		// 		-o:none
		// 		-o:minimal
		// 		-o:size
		// 		-o:speed
		// 		-o:aggressive (use this with caution)
		// The default is -o:minimal.


		os.make_directory("bin")
		o:string
		debug:bool = false
		if strings.compare(setting["build-type"].(json.String), "minimal") == 0 {
			o = "-o:minimal"
			debug = true
		} else {
			o = strings.join({"-o:", setting["build-type"].(json.String)}, "", context.temp_allocator)
		}
		//defer free_all(	context.temp_allocator)

		if !findGLSLFileAndRunCmd() do return

		if !runCmd({"odin", "build", 
		setting["main-package-path"].(json.String), 
		"-no-bounds-check" if !debug else ({}),
		out_path, 
		o, 
		"-debug" if debug else ({}),
		//"-sanitize:address" if debug else ({}),
		({}) if !is_android else "-define:__ANDROID__=true"}) {
			return
		}

		if is_android {
		}
	}
}

findGLSLFileAndRunCmd :: proc() -> bool {
	dir, err := os2.open("./xfit/shaders")
	if err != nil {
		fmt.panicf("findGLSLFiles open ERR : %s", err)
	}
	defer os2.close(dir)


	files, readErr := os2.read_dir(dir, 0, context.allocator)
	if readErr != nil {
		fmt.panicf("findGLSLFiles read_dir ERR : %s", readErr)
	}

	defer delete(files)
	for file in files {
		if file.type != .Regular do continue

		ext := filepath.ext(file.name)

		glslExts := []string{
			".glsl", ".vert", ".frag", ".geom", ".comp", 
			".tesc", ".tese", ".rgen", ".rint", ".rahit", 
			".rchit", ".rmiss", ".rcall"
		}

		for vExt in glslExts {
			if strings.compare(ext, vExt) == 0 {
				spvFile := strings.concatenate({"./xfit/shaders/", file.name, ".spv"})
				glslFile := strings.concatenate({"./xfit/shaders/", file.name})
				defer delete(spvFile)
				defer delete(glslFile)

				if !runCmd({"glslc", glslFile, "-O", "-o", spvFile}) do return false
				break
			}
		}
	}

	return true
}

runCmd :: proc(cmd:[]string) -> bool {
	r, w, err := os2.pipe()
	if err != nil do panic("pipe")

	p: os2.Process
	p, err = os2.process_start(os2.Process_Desc{
		command = cmd,
		stdout  = w,
		stderr  = w,
	})
	os2.close(w)

	output, err2 := os2.read_entire_file_from_file(r, context.temp_allocator)
	if err2 != nil do fmt.panicf("read_entire_file_from_file %v", err)

	
	if err != nil {
		fmt.eprint(string(output), err)

		os2.close(r)
		_ = os2.process_close(p)
		return false
		//fmt.panicf("%v", err)
	} else {
		state:os2.Process_State
		state, err = os2.process_wait(p)

		if state.exit_code != 0 {
			fmt.eprint(string(output))

			os2.close(r)
			_ = os2.process_close(p)
			return false
		}

		fmt.print(string(output))
		if err != nil do panic("process_wait")
	}
	_ = os2.process_close(p)

	return true
}