{ pkgs }:
let
  domain = "fish.foo";

  categories = [
    {
      name = "bitcoin";
      children = [
        {
          name = "benchmarking";
          links = [
            {
              name = "benchcoin";
              url = "https://bitcoin-dev-tools.github.io/benchcoin/";
              desc = "Bitcoin Core IBD benchmark";
            }
          ];
        }
        {
          name = "ci";
          links = [
            {
              name = "cdash";
              url = "https://my.cdash.org/index.php?project=core";
              desc = "Bitcoin Core experimental CDash";
            }
          ];
        }
        {
          name = "monitoring";
          links = [
            {
              name = "dns-monitor";
              host = "dns-monitor";
              desc = "Bitcoin DNS seed monitor";
            }
            {
              name = "ipc-node-dashboard";
              host = "tracing";
              desc = "IPC node tracing dashboard";
            }
          ];
        }
        {
          name = "stats";
          links = [
            {
              name = "ci";
              url = "https://willcl-ark.github.io/bitcoin-core-ci-stats";
              desc = "Bitcoin Core CI stats";
            }
            {
              name = "dns-seed";
              url = "https://willcl-ark.github.io/dnsseedrs/";
              desc = "DNS seed data analysis";
            }
            {
              name = "github";
              url = "https://willcl-ark.github.io/bitcoin-github-stats/";
              desc = "Bitcoin Core GitHub repo stats";
            }
          ];
        }
      ];
    }
    {
      name = "communication";
      links = [
        {
          name = "irc-logs";
          host = "irc";
          desc = "IRC logs";
        }
      ];
    }
    {
      name = "media";
      links = [
        {
          name = "music";
          host = "music";
          desc = "Navidrome music server";
        }
        {
          name = "radio";
          host = "stream.radio";
          desc = "Icecast radio stream";
        }
      ];
    }
    {
      name = "tools";
      links = [
        {
          name = "copy";
          host = "copy";
          desc = "Files and more";
        }
        {
          name = "dns";
          host = "bitcoin";
          desc = "Bitcoin dns seed data text files";
        }
      ];
    }
  ];

  linkUrl = link: if link ? url then link.url else "https://${link.host}.${domain}";

  serializeLink = link: {
    inherit (link) name desc;
    url = linkUrl link;
  };

  serializeCat =
    cat:
    {
      inherit (cat) name;
    }
    // (
      if cat ? children then
        {
          children = map (sub: {
            inherit (sub) name;
            links = map serializeLink sub.links;
          }) cat.children;
        }
      else
        {
          links = map serializeLink cat.links;
        }
    );

  categoriesJson = builtins.toJSON (map serializeCat categories);

  html = ''
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${domain}</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/jquery.terminal/css/jquery.terminal.min.css">
    <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { height: 100%; }
    body { background: #0d0d0d; }
    #term {
      --color: #c8c8c8;
      --background: #0d0d0d;
      --font: "SF Mono", "Cascadia Code", "Fira Code", Menlo, Consolas, monospace;
      --size: 16px;
      height: 100%;
    }
    </style>
    </head>
    <body>
    <div id="term"></div>
    <script src="https://cdn.jsdelivr.net/npm/jquery"></script>
    <script src="https://cdn.jsdelivr.net/npm/jquery.terminal/js/jquery.terminal.min.js"></script>
    <script>
    (function() {
      var data = ${categoriesJson};
      var cwd = [];

      function getNode(path) {
        var node = data;
        for (var i = 0; i < path.length; i++) {
          var found = null;
          for (var j = 0; j < node.length; j++) {
            if (node[j].name === path[i]) { found = node[j]; break; }
          }
          if (!found) return null;
          node = found.children || found.links || [];
        }
        return node;
      }

      function promptStr() {
        var dir = "~/services" + (cwd.length ? "/" + cwd.join("/") : "");
        return "[[;#5fda6e;]guest@${domain}]:[[b;#5f9fd7;]" + dir + "]$ ";
      }

      function isDir(item) { return !!(item.children || item.links); }

      function dirEntry(item) {
        return "[[b;#5f9fd7;]" + item.name + "/]";
      }

      function linkEntry(item) {
        return "[[!;;;;;" + item.url + "]" + item.name + "]";
      }

      function entryNames(node) {
        return node.map(function(item) {
          return isDir(item) ? dirEntry(item) : linkEntry(item);
        }).join("  ");
      }

      function rpad(s, len) {
        while (s.length < len) s += " ";
        return s;
      }

      function measureTree(node) {
        var nameW = 0, descW = 0;
        node.forEach(function(item) {
          if (isDir(item)) {
            var n = item.name.length + 1;
            if (n > nameW) nameW = n;
            var sub = item.children || item.links || [];
            var sw = measureTree(sub);
            if (sw.n > nameW) nameW = sw.n;
            if (sw.d > descW) descW = sw.d;
          } else {
            if (item.name.length > nameW) nameW = item.name.length;
            if (item.desc.length > descW) descW = item.desc.length;
          }
        });
        return { n: nameW, d: descW };
      }

      function fmtLong(node, nw, dw) {
        var lines = [];
        node.forEach(function(item) {
          if (isDir(item)) {
            lines.push("[[b;#5f9fd7;]" + rpad(item.name + "/", nw) + "]");
          } else {
            lines.push("[[!;;;;;" + item.url + "]" + item.name + "]" + rpad("", nw - item.name.length) + "[[;#808080;]" + rpad(item.desc, dw) + "][[;#606060;]" + item.url + "]");
          }
        });
        return lines.join("\n");
      }

      function lsLong(node) {
        var w = measureTree(node);
        return fmtLong(node, w.n + 2, w.d + 2);
      }

      function lsRecursive(node, prefix, long, nw, dw) {
        var lines = [];
        lines.push("[[b;#5f9fd7;]" + prefix + ":]");
        if (long) {
          lines.push(fmtLong(node, nw, dw));
        } else {
          lines.push(entryNames(node));
        }
        node.forEach(function(item) {
          if (isDir(item)) {
            var sub = item.children || item.links || [];
            var path = prefix + "/" + item.name;
            lines.push("");
            lines = lines.concat(lsRecursive(sub, path, long, nw, dw));
          }
        });
        return lines;
      }

      function findLinkIn(node, name) {
        for (var i = 0; i < node.length; i++) {
          var item = node[i];
          if (item.url && item.name === name) return item;
          if (item.links) {
            for (var j = 0; j < item.links.length; j++) {
              if (item.links[j].name === name) return item.links[j];
            }
          }
          if (item.children) {
            var r = findLinkIn(item.children, name);
            if (r) return r;
          }
        }
        return null;
      }

      function findLinkByPath(path) {
        var parts = path.split("/");
        var name = parts.pop();
        var base = cwd.concat(parts);
        var node = getNode(base);
        if (!node) return null;
        return findLinkIn(node, name);
      }

      function serviceNamesAt(node) {
        var names = [];
        node.forEach(function(item) {
          if (item.url) { names.push(item.name); return; }
          if (item.links) item.links.forEach(function(l) { names.push(l.name); });
          if (item.children) names = names.concat(serviceNamesAt(item.children));
        });
        return names.sort();
      }

      function dirNamesAt(node) {
        var names = [];
        node.forEach(function(item) {
          if (item.children || item.links) names.push(item.name);
        });
        return names.sort();
      }

      var banner = [
        "[[;#5f9fd7;]\u2591\u2588\u2580\u2580\u2591\u2580\u2588\u2580\u2591\u2588\u2580\u2580\u2591\u2588\u2591\u2588\u2591\u2591\u2591\u2591\u2588\u2580\u2580\u2591\u2588\u2580\u2588\u2591\u2588\u2580\u2588]",
        "[[;#5f9fd7;]\u2591\u2588\u2580\u2580\u2591\u2591\u2588\u2591\u2591\u2580\u2580\u2588\u2591\u2588\u2580\u2588\u2591\u2591\u2591\u2591\u2588\u2580\u2580\u2591\u2588\u2591\u2588\u2591\u2588\u2591\u2588]",
        "[[;#5f9fd7;]\u2591\u2580\u2591\u2591\u2591\u2580\u2580\u2580\u2591\u2580\u2580\u2580\u2591\u2580\u2591\u2580\u2591\u2580\u2591\u2591\u2580\u2591\u2591\u2591\u2580\u2580\u2580\u2591\u2580\u2580\u2580]",
        ""
      ].join("\n");

      var helpText = [
        "[[b;#c8c8c8;]Commands:]",
        "  [[b;#5fda6e;]ls] [-lR] [dir]  List services (-l long, -R recursive)",
        "  [[b;#5fda6e;]cd] <dir>        Change directory (use [[b;#5fda6e;]..] to go up)",
        "  [[b;#5fda6e;]open] <name>     Open a service in a new tab",
        "  [[b;#5fda6e;]info] <name>     Show service URL and description",
        "  [[b;#5fda6e;]clear]           Clear the terminal",
        "  [[b;#5fda6e;]help]            Show this message"
      ].join("\n");

      var term = $("#term").terminal(function(command) {
        command = command.trim();
        if (!command) return;
        var parts = command.split(/\s+/);
        var cmd = parts[0];
        var args = parts.slice(1);
        switch (cmd) {
          case "ls":
            var flags = [];
            var lsPath = null;
            for (var i = 0; i < args.length; i++) {
              if (args[i].charAt(0) === "-") {
                for (var c = 1; c < args[i].length; c++) flags.push(args[i].charAt(c));
              } else {
                lsPath = args[i];
              }
            }
            var hasR = flags.indexOf("R") >= 0;
            var hasL = flags.indexOf("l") >= 0;
            var target = cwd.slice();
            if (lsPath) {
              lsPath.split("/").forEach(function(s) {
                if (s === "..") { if (target.length) target.pop(); }
                else if (s && s !== ".") target.push(s);
              });
            }
            var node = getNode(target);
            if (!node) {
              this.error("ls: " + lsPath + ": No such directory");
            } else if (node.length === 0) {
              this.echo("(empty)");
            } else if (hasR) {
              var w = measureTree(node);
              this.echo(lsRecursive(node, ".", hasL, w.n + 2, w.d + 2).join("\n"));
            } else if (hasL) {
              this.echo(lsLong(node));
            } else {
              this.echo(entryNames(node));
            }
            break;
          case "cd":
            if (args.length === 0 || args[0] === "~") {
              cwd = [];
            } else {
              var segs = args[0].split("/");
              var next = cwd.slice();
              for (var i = 0; i < segs.length; i++) {
                if (segs[i] === ".." || segs[i] === "") {
                  if (next.length > 0) next.pop();
                } else {
                  next.push(segs[i]);
                }
              }
              if (getNode(next) !== null) {
                cwd = next;
              } else {
                this.error("cd: " + args[0] + ": No such directory");
                return;
              }
            }
            this.set_prompt(promptStr());
            break;
          case "open":
            if (args.length === 0) {
              this.error("Usage: open <service>");
              break;
            }
            var link = findLinkByPath(args[0]);
            if (link) {
              this.echo("Opening " + args[0] + "...");
              window.open(link.url, "_blank");
            } else {
              this.error(args[0] + ": service not found");
            }
            break;
          case "info":
            if (args.length === 0) {
              this.error("Usage: info <service>");
              break;
            }
            var link = findLinkByPath(args[0]);
            if (link) {
              this.echo("[[b;#c8c8c8;]" + link.name + "]  " + link.desc);
              this.echo("  [[!;;;;;" + link.url + "]" + link.url + "]");
            } else {
              this.error(args[0] + ": service not found");
            }
            break;
          case "help":
            this.echo(banner + helpText);
            break;
          case "motd":
            var msgs = [
              "Have you tried turning it off and on again?",
              "In a world of mass surveillance, encryption is a civil right.",
              "Don't trust. Verify.",
              "Running Bitcoin...",
              "There are only two hard things in computer science: cache invalidation, naming things, and off-by-one errors.",
              "The Times 03/Jan/2009 Chancellor on brink of second bailout for banks"
            ];
            this.echo("[[;#febc2e;]" + msgs[Math.floor(Math.random() * msgs.length)] + "]");
            break;
          case "whoami":
            this.echo("guest");
            break;
          case "pwd":
            this.echo("~/services" + (cwd.length ? "/" + cwd.join("/") : ""));
            break;
          case "uname":
            this.echo("FishFooOS 1.0.0 fish.foo " + navigator.platform + " GNU/Linux");
            break;
          case "cat":
            if (args.length === 0) { this.error("cat: missing operand"); break; }
            var link = findLinkByPath(args[0]);
            if (link) {
              this.echo(link.desc + "\n[[;#606060;]" + link.url + "]");
            } else {
              this.error("cat: " + args[0] + ": No such file");
            }
            break;
          case "exit":
          case "logout":
            this.echo("[[;#808080;]There is no escape. Type [[b;#5fda6e;]help] for commands.]");
            break;
          case "sudo":
            this.echo("[[;#ff5f57;]Nice try.]");
            break;
          case "rm":
            this.echo("[[;#ff5f57;]I'm afraid I can't let you do that.]");
            break;
          case "clear":
            this.clear();
            break;
          default:
            this.error(cmd + ": command not found. Type [[b;#5fda6e;]help] for available commands.");
        }
      }, {
        greetings: false,
        prompt: promptStr(),
        onInit: function() {
          var t = this;
          t.set_prompt("");
          t.echo(banner);
          t.typing("echo", 1, helpText, function() {
            t.echo("");
            t.set_prompt(promptStr());
          });
        },
        checkArity: false,
        keymap: {
          "CTRL+D": function() {
            this.echo("[[;#808080;]logout]");
            this.echo("[[;#808080;]Connection to ${domain} closed.]");
            this.disable();
          }
        },
        wordAutocomplete: false,
        completionEscape: false,
        completion: function(string, callback) {
          var commands = ["ls", "cd", "open", "info", "clear", "help"];
          var before = this.before_cursor();
          var parts = before.split(/\s+/);
          if (parts.length <= 1) {
            callback(commands.filter(function(c) { return c.indexOf(parts[0]) === 0; }));
            return;
          }
          var cmd = parts[0];
          var arg = parts[parts.length - 1] || "";
          var segs = arg.split("/");
          var partial = segs.pop();
          var base = cwd.slice();
          segs.forEach(function(s) {
            if (s === "..") { if (base.length) base.pop(); }
            else if (s && s !== ".") base.push(s);
          });
          var prefix = segs.length ? segs.join("/") + "/" : "";
          var node = getNode(base);
          if (!node) { callback([]); return; }
          var names = [];
          if (cmd === "cd") {
            names = dirNamesAt(node);
            if (base.length > 0 || cwd.length > 0) names.unshift("..");
          } else if (cmd === "ls") {
            names = dirNamesAt(node).concat(serviceNamesAt(node));
            if (base.length > 0 || cwd.length > 0) names.unshift("..");
          } else if (cmd === "open" || cmd === "info") {
            names = serviceNamesAt(node);
          }
          var matches = names.filter(function(n) { return n.indexOf(partial) === 0; });
          callback(matches.map(function(m) {
            var full = prefix + m;
            var isD = false;
            node.forEach(function(item) { if (item.name === m && isDir(item)) isD = true; });
            return cmd + " " + full + (isD ? "/" : "");
          }));
        }
      });
    })();
    </script>
    </body>
    </html>
  '';
in
pkgs.writeTextDir "index.html" html
