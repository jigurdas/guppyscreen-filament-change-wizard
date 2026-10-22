# Spoolman spool picker for the Filament Change wizard.
#
# FC_SPOOL_PROMPT asks Moonraker's Spoolman proxy for the spools and shows
# them as an "action:prompt" dialog. Each button runs the SELECT macro with
# ID=<spool id> (ID=0 means "skip"). The HTTP request runs in a thread so
# the Klipper reactor never blocks on the network.
#
# Copyright (C) 2026  jigurdas
#
# This file may be distributed under the terms of the GNU GPLv3 license.
import json, logging, threading
try:
    from urllib.request import Request, urlopen
except ImportError:
    from urllib2 import Request, urlopen

class FCSpoolman:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.gcode = self.printer.lookup_object('gcode')
        self.url = config.get('moonraker_url',
                              'http://127.0.0.1:7125').rstrip('/')
        self.max_spools = config.getint('max_spools', 30, minval=1)
        # GuppyScreen puts prompt buttons in one non-wrapping row, so the
        # list is split into pages of a few buttons each
        self.per_page = config.getint('per_page', 3, minval=1)
        self.timeout = config.getfloat('timeout', 5., above=0.)
        self.gcode.register_command("FC_SPOOL_PROMPT", self.cmd_FC_SPOOL_PROMPT,
                                    desc="Show the Spoolman spool picker")
    def _request(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = Request(self.url + path, data=data, method=method,
                      headers={"Content-Type": "application/json"})
        resp = urlopen(req, timeout=self.timeout)
        return json.loads(resp.read().decode()).get("result")
    def _fetch(self):
        spools = self._request("POST", "/server/spoolman/proxy", {
            "request_method": "GET", "path": "/v1/spool"})
        try:
            active = self._request("GET", "/server/spoolman/spool_id")
            active = (active or {}).get("spool_id")
        except Exception:
            active = None
        spools = [s for s in spools or [] if not s.get("archived")]
        # Active spool first, then most recently used
        head = [s for s in spools if s.get("id") == active]
        rest = sorted([s for s in spools if s.get("id") != active],
                      key=lambda s: s.get("last_used") or "", reverse=True)
        return active, (head + rest)[:self.max_spools]
    def _label(self, spool, active):
        fil = spool.get("filament") or {}
        parts = [fil.get("name", ""), fil.get("material", "")]
        label = " ".join(p for p in parts if p)
        weight = spool.get("remaining_weight")
        if weight is not None:
            label += " %dg" % (weight,)
        if spool.get("id") == active:
            label = "* " + label
        # "|" separates prompt button fields and quotes would end RESPOND
        return label.replace("|", "/").replace('"', "'").strip()
    def _show(self, eventtime, lines):
        for line in lines:
            self.gcode.respond_raw("// action:" + line)
    def _worker(self, select, cancel, page):
        # GuppyScreen only drops old buttons on prompt_end, so every dialog
        # starts by closing the previous one
        lines = ["prompt_end", "prompt_begin Select new spool"]
        more = None
        try:
            active, spools = self._fetch()
            pages = max(1, (len(spools) + self.per_page - 1) // self.per_page)
            page = page % pages
            if spools:
                text = "Choose the spool you are loading"
                if pages > 1:
                    text += " (%d/%d)" % (page + 1, pages)
                lines.append("prompt_text %s:" % (text,))
                start = page * self.per_page
                for s in spools[start:start + self.per_page]:
                    lines.append("prompt_button %s|%s ID=%d|primary" % (
                        self._label(s, active), select, s["id"]))
                if pages > 1:
                    more = "FC_SPOOL_PROMPT SELECT=%s CANCEL=%s PAGE=%d" % (
                        select, cancel, (page + 1) % pages)
            else:
                lines.append("prompt_text No spools found in Spoolman.")
        except Exception as e:
            logging.exception("fc_spoolman: can't load spools")
            lines.append("prompt_text Spoolman is not available (%s)."
                         % (str(e).replace('"', "'")[:80],))
        lines += ["prompt_footer_button Cancel|%s|error" % (cancel,),
                  "prompt_footer_button Skip|%s ID=0|secondary" % (select,)]
        if more:
            lines.append("prompt_footer_button More >|%s|info" % (more,))
        lines.append("prompt_show")
        self.reactor.register_async_callback(
            lambda eventtime: self._show(eventtime, lines))
    def cmd_FC_SPOOL_PROMPT(self, gcmd):
        select = gcmd.get("SELECT")
        cancel = gcmd.get("CANCEL", "_FC_CANCEL")
        page = gcmd.get_int("PAGE", 0, minval=0)
        if page == 0:
            self._show(None, ["prompt_end", "prompt_begin Select new spool",
                              "prompt_text Loading spools from Spoolman...",
                              "prompt_show"])
        t = threading.Thread(target=self._worker, args=(select, cancel, page))
        t.daemon = True
        t.start()

def load_config(config):
    return FCSpoolman(config)
