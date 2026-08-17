const __dyn_load = if ('~/.env.nu' | path exists) { '~/.env.nu' }
source $__dyn_load
source env.nu

# settings
$env.config.show_banner = "short"
$env.config.use_kitty_protocol = true
$env.config.filesize.unit = "metric"
$env.config.datetime_format.normal = "%m/%d/%y %H:%M:%S"
$env.config.datetime_format.table = "%m/%d/%y %H:%M:%S"
if not ($nu.data-dir | path exists) { mkdir $nu.data-dir }
$env.config.history.path = $nu.data-dir
$env.config.history.file_format = "sqlite"
$env.config.history.isolation = true
$env.config.history.ignore_space_prefixed = true
$env.config.completions.algorithm = "fuzzy" # prefix|substring|fuzzy
$env.config.completions.partial = false
$env.config.table.header_on_separator = true
$env.config.table.mode = "frameless" # light|compact|frameless
$env.config.max_last_result_size = 10mb

if not ($nu.data-dir | path exists) { mkdir $nu.data-dir }
if not ($nu.cache-dir | path exists) { mkdir $nu.cache-dir }

source plugin.nu

source keymaps.nu

const __dyn_load = if ('~/.nu' | path exists) { '~/.nu' }
source $__dyn_load
