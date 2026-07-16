# argx.nu 🚀

A language-aware, signature-driven, and completely unopinionated argument parsing engine built exclusively for Nushell autocomplete closures.
Instead of hacking fragile text-splitters or managing bloated external multi-shell engines, argx.nu interacts directly with Nushell's live internal Abstract Syntax Tree (AST) contexts and runtime command signatures. It dynamically maps an unordered, chaotic terminal input stream into a clean, normalized, and strongly-typed Record that is immediately actionable.

## ✨ Features

- 🧠 Language-Aware AST Tokenization: Correctly extracts complex Nushell types, nested quotes, and closures/subexpressions (e.g., blocks like {KEY: VALUE}) without breaking your completion pipe on white spaces or special characters.
- 🎯 Deep Alias Bypassing: [Core Advantage] Transparently penetrates user-defined aliases. Even if a shortcut alias (like dr) is typed in the terminal, argx.nu traces back to the underlying base command and outputs the true semantic intent in the tag field (e.g., container-create), saving your completion scripts from handling endless alias variations.
- 🔄 Signature-Driven Argument Normalization:
- Options (Flags): Automatically resolves command definitions to normalize short flags (e.g., -e, -p) into their canonical long-form parameter names (e.g., envs, ports), eliminating duplicate alias-handling logic in your code.
   - Positional Arguments: Maps raw positional strings into their exact variable names defined in the command's original signature (e.g., mapping localhost/... to pos.image). This completely solves the common "index-shifting" problem caused by omitted optional positionals or rearranged inputs.
- 🛡️ Execution-Safe (Zero Side-Effects): Keeps nested commands and closures frozen as raw AST structures during the Tab-completion phase, ensuring you never accidentally trigger heavy or dangerous sub-commands.
- 🏷️ High-Fidelity Semantic Mapping: Structurizes tokens cleanly into named options (opt), raw post-arguments (args), typed positional fields (pos), and inferred operation intent identifiers (tag).
- 🪶 Zero-DSL Philosophy: No proprietary wrapper commands or rigid state-machine APIs to learn. It returns a pure Nushell Record so you can use 100% of your existing Nushell skills (match, if, get, where).

## 🔍 How It Works (The Ultimate Debug DX)
One of the cleanest developer experiences with argx.nu is that you can perfectly snapshot, test, and introspect your live autocomplete logic as a static data frame directly in your prompt by simply passing your CLI line as a string.
Notice in the example below how the shortcut alias dr is decoded, short flags -e and -p are mapped to long forms, and the anonymous positional path string is cleanly resolved to its signature parameter name:

```nu
'dr -e {OPENAI_API_KEY: (asn --all | get api_key)} -p {8000:8000} skill:latest' | argx parse
```

## 📦 Actual Output Schema
argx.nu instantly extracts the developer's exact intent into this clear data structure:

```yml
args:
  - localhost/test-skill:latest
opt:
  envs:  # 👈 Automatically normalized from short flag -e to signature long-form 'envs'
    OPENAI_API_KEY: (asn --all | get api_key)  # Safely captured as a block/AST structure without invocation
  ports: # 👈 Automatically normalized from short flag -p to signature long-form 'ports'
    '8000': 8000
  sshuser: root
tag: container-create  # 👈 Bypasses the typed alias 'dr' to reveal the true underlying command intent
pos:  # 👈 Maps raw positionals into stable, semantic signature parameter names
  image: skill:latest
  cmd: []
```

## 💡 Example 1: Seamless Kubernetes Resource Autocompletion
When writing intelligent completions for Kubernetes (kubectl), you often need to fetch live cluster resources based on the current command context—such as the resource type specified by positional arguments, or the target namespace provided via flags.
With argx.nu, you can implement a dynamic resource completer using compact, idiomatic Nushell code that completely decouples short and long flag logic:

A dynamic completer for Kubernetes resource names
```nu
export def cmpl-kube-res [context: string, offset: int] {
    # 1. Pipe the context into argx parse to get a highly structured record
    let ctx = $context | argx parse
    
    # 2. Reliably extract the first positional argument (e.g., pod, svc, deployment)
    let kind = $ctx | get args.0
    
    # 3. Core Strength: Thanks to automatic long-form normalization, whether the user 
    #    typed `-n` or `--namespace`, you can safely read it via `.namespace?` in one line.
    let ns = if ($ctx.opt.namespace? | is-empty) { [] } else { [-n $ctx.opt.namespace] }
    
    # 4. Query kubectl live to fetch instances matching the resolved namespace and kind
    kubectl get ...$ns $kind | from ssv -a | get NAME
}
```

## 💡 Example 2: AI vs. Idiomatic Nushell (Architecture Showdown)

Writing great Nushell completions isn't just about parsing the current context—it requires structuring your command signatures so that metadata naturally flows from left to right exactly when the user presses Tab.
Many Large Language Models (AI) generate Nushell scripts using traditional, non-interactive CLI habits inherited from Bash or Python argparse. Below is a head-to-head comparison between a standard AI-generated script and an idiomatic, argx.nu-driven architecture.

### ❌ The Non-Interactive Approach (AI Version)
This implementation treats options as trailing flags and requires a rigid positional layout, which completely breaks live shell interactivity:

AI-Generated Version
```nu
export def qemu-snapshot-ai [
  disk: path
  name: string
  --action: string
] {
  match $action {
    "create" => { qemu-img snapshot -c $name $disk }
    "apply"  => { qemu-img snapshot -a $name $disk }
    "delete" => { qemu-img snapshot -d $name $disk }
    "list"   => { qemu-img snapshot -l $disk }
    _        => { error make { msg: "unknown action" } }
  }
}
```

#### Why the AI Version Fails the Developer Experience (DX):
- Blind Autocomplete (The Dead End): Because Nushell evaluates syntax trees linearly from left to right, a user must type the disk path and the snapshot name before they ever declare the --action. When the user is at the name parameter, the shell has no way of knowing whether they are trying to delete an existing snapshot or create a new one. Dynamic context suggestion becomes impossible.
- Artificial Boilerplate: For the list action, the name argument is completely ignored by the underlying qemu-img command. However, because it is a required positional argument in the AI's signature, the user is forced to pass a dummy placeholder string (e.g., qemu-snapshot-ai ./disk.qcow2 dummy --action list) just to satisfy the syntax compiler.
- Monolithic Code Duplication: The shell invocation logic is mechanically duplicated four separate times.

### The Signature-Driven Approach (Idiomatic Version)
By inverting the parameter priority and leveraging argx.nu to extract live signature mappings, the command layout is streamlined for natural human typing and powerful terminal dropdown UI feedback:

#### 1. The Context-Aware Completer
```nu
def cmpl-snapshot [context] {
    use argx
    let c = $context | argx parse
    
    # Safely expand the disk path extracted by its canonical signature name
    qemu-img info --out=json ($c.pos.disk | path expand)
    | from json 
    | get -i snapshots
    | default []
    | each {|x|
        # Format raw integers into rich, aligned dropdown descriptions
        let date = $x.date-sec * 1000_000_000 | into datetime
        let size = $x.vm-state-size  | into filesize
        { value: $x.name, description: $"($date)(char tab)($size)" }
    }
    # Bypasses native alphabetical sorting to preserve QEMU's natural order
    | { completions: $in, options: { sort: false } }
}
```

#### 2. The Idiomatic Command Layout
```nu
export def qemu-snapshot [
    action: string@[create apply delete list]
    disk: path
    name?: string@cmpl-snapshot   # Optional parameter driven by context
] {
    mut args = []
    $args ++= [(match $action {
        create => '-c'
        apply => '-a'
        delete => '-d'
        list => '-l'
    })]
    $args ++= [$disk]
    if ($name | is-not-empty) {
        $args ++= [$name]
    }
    
    qemu-img snapshot ...$args
}
```

#### Why the Idiomatic Version Prevails:

- Linear Context Flow: By declaring action and disk before name, you ensure that when the user's cursor hits the name parameter and strikes Tab, both critical parameters have already been compiled into active AST structures. argx.nu instantly intercepts them.
- Zero-Index Dependency Guessing: Inside cmpl-snapshot, you don't have to guess which array index the disk path belongs to using fragile text splitting. argx.nu maps it securely to $c.pos.disk. Passing it through path expand guarantees that the completion engine won't break due to working directory mismatches if the user provided a relative path (./vdisk.img).
- UI Fidelity & Lean Controls: The name? parameter is kept optional. If the user picks list, they provide the action and the disk path, press Enter, and it runs smoothly without garbage parameters. If they pick apply or delete, they strike Tab and get a highly polished dropdown menu containing formatted, tab-separated datetimes and file sizes pulled directly from the target QEMU layer.

### 📊 Engineering Board

| Dimension | The Non-Interactive Approach (AI) | The Signature-Driven Approach (argx.nu) |
|---|---|---|
| Signature Blueprint | ❌ Rigid. Blindly copy-pastes generic script signatures. | Idiomatic. Tailored around left-to-right user interaction. |
| Tab-Completion | ❌ Blind. Cannot read states because controls sit at the end. | 🚀 Predictive. Seamlessly queries disk state based on preceding arguments. |
| Input Cleanness | ❌ Bloated. Forces dummy argument payloads for standard list commands. | Lean. name? is decoupled and only prompted when logically required. |
| Execution Block | ❌ Redundant. Linearly duplicates system orchestration blocks. | Elegant. Bundles arguments into a mutable array via ...$args splatting. |

## 🧠 Design Decisions & Tradeoffs
During the development and testing of argx.nu, several common architectural questions and alternative approaches were explored. Below are the core design choices that shape the library today.

### 1. Why output a pure Record instead of providing fluent helper filters (like argx when-tag)?

- Decision: Keep the library strictly bounded as a pure data extractor.
- Rationale: Introducing a custom Domain-Specific Language (DSL) or proprietary wrapper utilities creates an artificial learning curve. Nushell users already know how to fluently manipulate data using core native tools like match, if/else, get, and where. By returning an unopinionated, strongly-typed Record, developers can leverage 100% of their existing Nushell skills without reading a secondary API reference manual.

### 2. Why doesn't argx recursively evaluate subexpressions/closures (e.g., statements inside ( ) or { }) to pass their live values to parent commands?

- Decision: Keep nested blocks frozen as raw AST representations during the autocomplete phase.
- Rationale:
   - Boundary Isolation: When a user types a subexpression (e.g., (nested-cmd)), control is handed over entirely to Nushell's engine to execute a completely independent syntax tree. It is outside the scope of the parent command parser.
   - Execution Safety: Running arbitrary commands during the live typing/Tab-completion phase is highly dangerous. Doing so could trigger unintended mutations, long network timeouts, or heavy CPU tasks (e.g., if a subexpression contains destructive flags or complex API requests). argx enforces strict, side-effect-free safety by treating nested syntax trees statically.

### 3. Why not use a strict State Machine or Tree-based configuration for dynamic completions?

- Decision: Avoid opinionated state-management frameworks and focus purely on context extraction.
- Rationale: Standard multi-shell completion frameworks often enforce rigid tree structures, assuming a predictable user flow (Command ➔ Subcommand ➔ Flag ➔ Value). However, human interactive typing is messy and non-linear—users routinely inject flags out of order, insert global flags halfway, or jump back and forth in the prompt. Strict state machines suffer from exponential state-graph explosion under these conditions. By providing raw, normalized context snapshotting instead, argx allows you to write non-linear, zero-boilerplate matching logic that remains resilient regardless of input order.


# TODO
- [x] parse `parameter_default` (get-sign)
- [x] select the corresponding item in the `pipelines` based on the `offset` (get-ast)
- [x] parse filepath type
---
[Others](https://github.com/orbsh/nushell/blob/main/README.md)
