@our_log = (o) ->
    if console? && console.log?
        console.log.apply(console, if !!arguments.length then arguments else [this])
    else if opera? && opera.postError?
        opera.postError(o || this)

@log_info = (o) -> log_msg("INFO", arguments)
@log_warn = (o) -> log_msg("WARN", arguments)
@log_error = (o) -> log_msg("ERROR", arguments)
@log_debug = (o) ->
    log_msg("DEBUG", arguments) if window.debug?

# Our internal log allowing a log type
log_msg = (msg,rest) ->
    args = Array.prototype.slice.call(rest)
    r = [msg].concat(args)
    window.our_log.apply(window, r)