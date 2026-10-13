# ROADMAP section 63. A workflow_dispatch release (umbrella-release.yml takes a free-text `tag`) used to build the dotnet binaries
# from the DISPATCH branch, because the two actions/checkout steps in build-dotnet.yml carried no `ref:`; the version, the build
# and the asset names then came from that branch, and `publish` attached them to the tag's release. build-dotnet.yml now takes an
# optional `ref` input that both checkouts use, and umbrella-release.yml passes the tag.
#
# WHAT THIS PINS, and what it cannot: the TEXT of the three workflow files, read as text (no YAML parser: this box has no yq, and
# a regex over a fixed layout is enough to pin the wiring). It cannot prove that GitHub resolves `github.event.inputs.tag ||
# github.ref_name` inside a `uses:` job's `with:` the way the documentation says; only a real release proves that (ROADMAP section 63).
# republish-member.yml must NOT pass a ref: a hotfix republish deliberately rebuilds the dispatch branch onto an existing tag.
BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    function Read-Workflow([string]$Name) { Get-Content -Raw -LiteralPath (Join-Path $script:Root ".github/workflows/$Name") }
    # Every actions/checkout step in the text, as @{ Line = <the uses line>; Ref = <the trimmed `ref:` value or $null> }.
    function Get-Checkouts([string]$Text) {
        $out = @()
        foreach ($m in [regex]::Matches($Text, '(?m)^[ ]*- uses: actions/checkout@\S+[ ]*\r?\n(?<with>(?:[ ]+(?:with:|\S+:.*)\r?\n)*)')) {
            $ref = [regex]::Match($m.Groups['with'].Value, '(?m)^[ ]+ref:[ ]*(?<v>.*?)[ ]*\r?$')
            $out += [pscustomobject]@{ Ref = $(if ($ref.Success) { $ref.Groups['v'].Value } else { $null }) }
        }
        return , $out
    }
    # The text of one top-level job (two-space indent) up to the next job.
    function Get-JobText([string]$Text, [string]$Job) {
        $m = [regex]::Match($Text, "(?ms)^  $([regex]::Escape($Job)):\r?\n(?<body>.*?)(?=^  \S|\z)")
        $m.Success | Should -BeTrue -Because "job '$Job' must exist"
        return $m.Groups['body'].Value
    }
}

Describe 'a release builds the TAG it was asked to release' {
    It 'build-dotnet.yml declares an optional string input `ref` that defaults to empty' {
        $t = Read-Workflow 'build-dotnet.yml'
        $m = [regex]::Match($t, '(?ms)^  workflow_call:\r?\n    inputs:\r?\n      ref:\r?\n(?<body>.*?)^    outputs:')
        $m.Success | Should -BeTrue
        $m.Groups['body'].Value | Should -Match "(?m)^        type: string\r?$"
        $m.Groups['body'].Value | Should -Match "(?m)^        default: ''\r?$"
        $m.Groups['body'].Value | Should -Match '(?m)^        required: false\r?$'
    }

    It 'EVERY actions/checkout in build-dotnet.yml passes ref: ${{ inputs.ref }} (two of them: validate and build)' {
        $c = Get-Checkouts (Read-Workflow 'build-dotnet.yml')
        $c.Count | Should -Be 2 -Because 'a third checkout would need the same ref, and one fewer means the matcher lost one'
        foreach ($x in $c) { $x.Ref | Should -BeExactly '${{ inputs.ref }}' }
    }

    It 'the checkout matcher REJECTS a near miss (a different expression, no with: block, a commented ref)' {
        $syn = @'
jobs:
  a:
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ inputs.tag }}
      - uses: actions/checkout@v7
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
'@
        $c = Get-Checkouts $syn
        $c.Count | Should -Be 3
        $c[0].Ref | Should -BeExactly '${{ inputs.tag }}'
        $c[1].Ref | Should -BeNullOrEmpty
        $c[2].Ref | Should -BeNullOrEmpty
    }

    It 'umbrella-release.yml passes the TAG to its dotnet build: the dispatch input, else the pushed tag name' {
        $job = Get-JobText (Read-Workflow 'umbrella-release.yml') 'dotnet'
        $job | Should -Match '(?m)^    uses: \./\.github/workflows/build-dotnet\.yml[ ]*\r?$'
        $job | Should -Match '(?m)^      ref: \$\{\{ github\.event\.inputs\.tag \|\| github\.ref_name \}\}[ ]*\r?$'
    }

    It 'the dotnet publish stamps the plugin version, and the smoke step REJECTS a --version that does not name it (stale-client stamp)' {
        $t = Read-Workflow 'build-dotnet.yml'
        $t | Should -Match '(?m)^          v="\$\{\{ needs\.validate\.outputs\.version \}\}"\r?$'
        # v must be set BEFORE the publish that uses it (it used to be assigned only after the publish).
        $t.IndexOf('v="${{ needs.validate.outputs.version }}"') | Should -BeLessThan $t.IndexOf('dotnet publish src/Clavity.Cli')
        $t | Should -Match '(?m)^\s+-p:Version="\$v" -p:PublishSingleFile=true'
        # The accepted outputs are the bare version or version+metadata: a prefix match would also accept 0.11.00.
        $t | Should -Match ([regex]::Escape('"clavity-ls $v"|"clavity-ls $v+"*)'))
        $t | Should -Match "exit 1 ;;\r?\n\s+esac"
    }

    It 'republish-member.yml passes NO ref to its dotnet build (a hotfix rebuilds the dispatch branch on purpose)' {
        $job = Get-JobText (Read-Workflow 'republish-member.yml') 'dotnet'
        $job | Should -Match '(?m)^    uses: \./\.github/workflows/build-dotnet\.yml'
        $job | Should -Not -Match '(?m)^\s+ref:'
        $job | Should -Not -Match '(?m)^    with:'
    }
}
