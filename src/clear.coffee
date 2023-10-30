fs = require "fs"
{execSync} = require "child_process"
{cache_path} = require "./config"

module.exports = (opt, cb)->
  if !fs.existsSync cache_path
    return cb()
  
  list = fs.readdirSync cache_path
  if list.length
    execSync "rm -rf #{cache_path}/*"
  
  cb()
