using Test
using Openresty
using HTTP

function createconfig(workdir::String)
    cfg = """worker_processes  1;
error_log $workdir/logs/error.log debug;
events {
    worker_connections  1024;
}
http {
    access_log $workdir/logs/access.log;
    error_log $workdir/logs/error.log debug;
    lua_package_path 'OPENRESTY_LUA_PACKAGE_PATH';
    include       mime.types;
    server {
        listen 8080;
        server_name localhost;
        root $workdir/html;
        index index.html index.htm index.nginx-debian.html;
    }
}
"""
    cfgfile = joinpath(workdir, "test.conf")

    open(cfgfile, "w") do f
        println(f, cfg)
    end

    cfgfile
end

function test_nginx_config()
    body = ""

    @info("waiting for nginx to come up")
    # try for 10 secs
    while isempty(body)
        sleep(2)
        try
            resp = HTTP.get("http://127.0.0.1:8080/")
            body = String(resp.body)
        catch ex
            @info("nginx not ready yet...")
        end
    end

    isempty(body) && error("nginx did not come up")

    @info("testing nginx response")
    @test occursin("Welcome to OpenResty", body)
    nothing
end

function test()
    workdir = mktempdir()
    mkpath(workdir)
    cfgfile = createconfig(workdir)
    nginx = OpenrestyCtx(workdir)

    tmpdir1 = mktempdir()
    tmpdir2 = mktempdir()
    @info("setting up Openresty", workdir, tmpdir1, tmpdir2)

    # incorrect lua path should throw error
    @test_throws Exception setup(nginx, cfgfile; lua_package_path=joinpath(tmpdir1, "mylualibs"))
    # setup with correct lua path
    @test nothing === setup(nginx, cfgfile; lua_package_path=tmpdir1)
    @test isfile(Openresty.conffile(nginx))
    confstr = read(Openresty.conffile(nginx), String)
    userlib1 = joinpath(Openresty.user_lua_lib_folder(nginx,tmpdir1), "?.lua")
    syslib = "$(Openresty.luadir(nginx))/lualib/?.lua"
    @test occursin(userlib1, confstr)
    @test occursin(syslib, confstr)
    @test occursin("$syslib;$userlib1;;", confstr)

    @info("starting Openresty")
    start(nginx)
    sleep(2)
    @test isfile(Openresty.pidfile(nginx))
    @test isrunning(nginx)

    test_nginx_config()

    @info("restarting Openresty")
    restart(nginx; delay_seconds=2)
    sleep(2)
    @test isfile(Openresty.pidfile(nginx))
    @test isrunning(nginx)
    @test nothing === reopen(nginx)
    @test nothing === reload(nginx)

    test_nginx_config()

    @info("stopping Openresty")
    stop(nginx)
    sleep(2)
    @test !isfile(Openresty.pidfile(nginx))
    @test !isrunning(nginx)
    @test isfile(Openresty.accesslogfile(nginx))
    @test isfile(Openresty.errorlogfile(nginx))

    @test_throws Exception setup(nginx, cfgfile)
    @test nothing === setup(nginx, cfgfile; force=true)
    @test nothing === setup(nginx, cfgfile; force=true, lua_package_path=[tmpdir1, tmpdir2])

    @info("cleaning up")
    rm(workdir; recursive=true, force=true)
    rm(tmpdir1; recursive=true, force=true)
    rm(tmpdir2; recursive=true, force=true)
    @info("done")

    nothing
end

test()
