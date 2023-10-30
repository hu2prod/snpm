#!/usr/bin/env iced
fs = require "fs"
require "fy"
argv = require("minimist")(process.argv.slice(2))

cb = (err)->
  if err
    throw err
  puts "done"
  process.exit()

# ###################################################################################################
if !cmd = argv._[0]
  puts "usage"
  puts "  snpm i"
  puts "  snpm clear"
  process.exit(1)

switch cmd
  when "i", "install"
    fn = require("./install")
  
  when "clear"
    fn = require("./clear")
  
  else
    perr "snpm can't do anything except install"
    process.exit(1)

await fn {}, defer(err); return cb err if err

cb()
