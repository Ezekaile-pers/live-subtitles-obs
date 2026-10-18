# Runs tests/lua/script.test.lua inside LuaJIT from OBS (lua51.dll) and prints what the test chunk returns:
# "ok N" or "FAIL ...". Usage: powershell -NoProfile -ExecutionPolicy Bypass -File run.ps1 [-Lua path\to\lua51.dll]
param(
  [string]$Lua = 'C:\Program Files\obs-studio\bin\64bit\lua51.dll',
  [string]$Test = ''
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
if (-not (Test-Path $Lua)) { Write-Output "SKIP no lua51.dll at $Lua"; exit 0 }
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Test) { $Test = Join-Path $here 'script.test.lua' }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class LuaHost {
  [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr LoadLibraryW(string path);
  [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl)] static extern IntPtr luaL_newstate();
  [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl)] static extern void luaL_openlibs(IntPtr L);
  [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl)] static extern int luaL_loadbuffer(IntPtr L, byte[] buff, UIntPtr size, string name);
  [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl)] static extern int lua_pcall(IntPtr L, int nargs, int nresults, int errfunc);
  [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl)] static extern IntPtr lua_tolstring(IntPtr L, int idx, out UIntPtr len);
  [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl)] static extern void lua_settop(IntPtr L, int idx);
  [DllImport("lua51.dll", CallingConvention = CallingConvention.Cdecl)] static extern void lua_close(IntPtr L);

  static string Top(IntPtr L) {
    UIntPtr len;
    IntPtr p = lua_tolstring(L, -1, out len);
    if (p == IntPtr.Zero) return "(nil)";
    byte[] bytes = new byte[(int)len];
    Marshal.Copy(p, bytes, 0, bytes.Length);
    return Encoding.UTF8.GetString(bytes);
  }

  static int Run(IntPtr L, byte[] code, string name) {
    int rc = luaL_loadbuffer(L, code, (UIntPtr)code.Length, name);
    if (rc == 0) rc = lua_pcall(L, 0, 1, 0);
    return rc;
  }

  public static string Exec(string dll, string prelude, string testFile) {
    if (LoadLibraryW(dll) == IntPtr.Zero) return "FAIL cannot load " + dll;
    IntPtr L = luaL_newstate();
    luaL_openlibs(L);
    try {
      if (Run(L, Encoding.UTF8.GetBytes(prelude), "=prelude") != 0) return "FAIL prelude: " + Top(L);
      lua_settop(L, 0);
      if (Run(L, System.IO.File.ReadAllBytes(testFile), "@" + System.IO.Path.GetFileName(testFile)) != 0) return "FAIL " + Top(L);
      return Top(L);
    } finally {
      lua_close(L);
    }
  }
}
'@

$dir = ($here -replace '\\', '/') + '/'
$result = [LuaHost]::Exec($Lua, "TEST_DIR = [[$dir]]", $Test)
Write-Output $result
if ($result -notmatch '^ok ') { exit 1 }
