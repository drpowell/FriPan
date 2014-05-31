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

html_warning = """
    <div class='browser-warning'>
      <button type="button" class="close" onclick="$('.browser-warning').hide();">x</button>
      <h1>Internet Explorer is not supported</h1>
      <p>Please use <a href='http://www.mozilla.org/en-US/firefox/new/'>Firefox</a> or <a href='http://www.google.com/chrome/'>Chrome</a></p>
    </div>
    """

# Display a popup warning, or fill in a warning box if using IE
@add_browser_warning = () ->
    if window.navigator.userAgent.indexOf("MSIE ")>=0
        outer = $('.browser-warning-outer')
        if outer.length==0
            # No container found, let's create a popup one
            $('body').prepend('<div class="warning-popover browser-warning-outer"></div>')
            outer = $('.browser-warning-outer')
        outer.append(html_warning)
