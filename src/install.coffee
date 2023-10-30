fs = require "fs"
os = require "os"
mod_path = require "path"
{exec, execSync} = require "child_process"
mkdirp = require "mkdirp"
semver = require "semver"
require "lock_mixin"
{cache_path} = require "./config"

# внезапно разные пакеты могут требовать одинаковых зависимостей
# и от этого ломается pnpm
exec_lock = new Lock_mixin

lock = new Lock_mixin
lock.$limit = os.cpus().length

pkg_check_and_move = (pkg, cb)->
  {name, version, cwd} = pkg
  
  folder_name = "snapshot_#{name}@#{version}"
  folder_name = folder_name.replace /[\/\#:]/g, "_"
  src_path = "#{cache_path}/#{folder_name}"
  src_path_direct = "#{src_path}/node_modules/#{name}"
  src_path_pnpm   = "#{src_path}/node_modules/.pnpm"
  dst_path        = "#{cwd}/node_modules/#{name}"
  dst_path_root   = "#{cwd}/node_modules/"
  dst_path_pnpm   = "#{cwd}/node_modules/.pnpm"
  dst_path_bin_root= "#{cwd}/node_modules/.bin"
  dst_path_bin    = "#{cwd}/node_modules/.bin/#{name}"
  
  # retry
  if fs.existsSync src_path
    if !fs.existsSync src_path_direct
      puts "REMOVE improperly installed pkg #{name}@#{version}"
      execSync "rm -rf #{src_path}"
  
  if !fs.existsSync src_path
    mkdirp.sync src_path
    pkg_str = "#{name}@#{version}"
    # github: немного странно работает
    # С одной стороны мне надо поддерживать git протокол и я не могу просто менять pkg_str
    # С другой стороны оно должно работать если у меня публичный пакет
    # KEEP for debug
    # execSync "pnpm i #{pkg_str}", cwd: src_path
    await exec_lock.wrap cb, defer(cb)
    # TODO логичнее было бы если бы version.startsWith "github:" проверка была здесь
    puts "need install #{pkg_str}"
    await exec "pnpm i #{pkg_str}", cwd: src_path, defer(err);
    if err
      if !version.startsWith "github:"
        return cb err
      
      [_skip, user, package_name] = /^(.*?)_(.*)$/.exec version
      pkg_str = "#{user}/#{package_name}"
      await exec "pnpm i #{pkg_str}", cwd: src_path, defer(err); return cb err if err
    
  if !fs.existsSync src_path_direct
    return cb new Error "pkg #{name}@#{version} not installed properly"
  
  if !fs.existsSync dst_path_root
    fs.mkdirSync dst_path_root
  
  if !fs.existsSync dst_path_bin_root
    fs.mkdirSync dst_path_bin_root
  
  if !fs.existsSync dst_path_pnpm
    fs.mkdirSync dst_path_pnpm
  
  if fs.existsSync dst_path
    # execSync "rm #{dst_path}"
    execSync "rm -rf #{dst_path}"
  
  # execSync "ln -s #{src_path_direct} #{dst_path}"
  execSync "cp -r #{src_path_direct} #{dst_path}"
  execSync "cp -r #{src_path_pnpm}/* #{dst_path_pnpm}"
  
  src_path_direct_bin = "#{src_path}/node_modules/.bin/#{name}"
  
  if fs.existsSync src_path_direct_bin
    if !fs.existsSync "#{cwd}/node_modules/.bin"
      fs.mkdirSync "#{cwd}/node_modules/.bin"
    if fs.existsSync dst_path_bin
      execSync "rm #{dst_path_bin}"
    # execSync "ln -s #{src_path_direct_bin} #{dst_path_bin}"
    # execSync "cp -r #{src_path_direct_bin} #{dst_path_bin}"
    # suppress Invalid cross-device link
    execSync "ln #{src_path_direct_bin} #{dst_path_bin} || ln -s #{src_path_direct_bin} #{dst_path_bin}"
  
  cb()

module.exports = (opt, cb)->
  opt.cwd ?= process.cwd()
  conf = JSON.parse fs.readFileSync "#{opt.cwd}/package.json", "utf-8"
  
  package_list = []
  handle_name_version = (name, version)->
    path_to_module = "#{opt.cwd}/node_modules/#{name}"
    if !fs.existsSync path_to_module
      package_list.push {name, version}
      return
    
    if version.startsWith "github"
      return
    
    target_package_json_file = "#{path_to_module}/package.json"
    if !fs.existsSync target_package_json_file
      package_list.push {name, version}
      return
    
    mod_package_json = JSON.parse fs.readFileSync target_package_json_file
    if !semver.satisfies mod_package_json.version, version
      package_list.push {name, version}
    return
  
  if conf.dependencies
    for name, version of conf.dependencies
      handle_name_version name, version
  
  if conf.devDependencies
    for name, version of conf.devDependencies
      handle_name_version name, version
  
  if !fs.existsSync "#{opt.cwd}/node_modules"
    fs.mkdirSync "#{opt.cwd}/node_modules"
  
  err_found = null
  for pkg in package_list
    pkg.cwd = opt.cwd
    do (pkg)->
      await lock.lock defer()
      if err_found
        lock.unlock()
        return
      
      unless opt.quiet
        puts "  #{pkg.name}@#{pkg.version}"
      
      await pkg_check_and_move pkg, defer(err);
      err_found = err if err
      
      lock.unlock()
  
  await lock.drain defer()
  if err_found
    return cb err_found
  
  cb()
