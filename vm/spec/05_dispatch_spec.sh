#!/usr/bin/env bash
# shellcheck shell=bash
# Dispatcher + arg-validation unit tests. Sub-second: no libvirt, no
# bib, no fork beyond the EXIT_USAGE assertions. Skips host preflight
# via VM_PREFLIGHT=none so this stays green on any host regardless of
# Fedora version.

Describe 'dispatch'
  Include "${VM_ROOT}/scripts/lib/common.sh"
  Include "${VM_ROOT}/scripts/lib/bib.sh"
  export VM_PREFLIGHT=none

  Describe 'vm create --target'
    It 'rejects an unknown target with EXIT_USAGE'
      When run script "${VM_BIN}" create --target nonexistent-foo --name probe
      The status should equal 64
      The stderr should include 'target not found'
    End
  End

  Describe 'vm build-kinoite --target'
    It 'rejects an unknown target with EXIT_USAGE'
      When run script "${VM_BIN}" build-kinoite --target nonexistent-foo
      The status should equal 64
      The stderr should include 'target env not found'
    End
  End

  Describe '_bib_out_subdir (pure)'
    It 'derives "kinoite-out" from kinoite.env (no override)'
      When call _bib_out_subdir 'kinoite.env'
      The output should equal 'kinoite-out'
    End

    It 'derives "kinoite-44-out" from kinoite-44.env (no override)'
      When call _bib_out_subdir 'kinoite-44.env'
      The output should equal 'kinoite-44-out'
    End

    It 'strips a leading directory prefix'
      When call _bib_out_subdir '/abs/path/to/targets/kinoite-44.env'
      The output should equal 'kinoite-44-out'
    End

    It 'derives "kinoite-out-kinoite-cockpit" for kinoite + cockpit override'
      When call _bib_out_subdir 'kinoite.env' 'kinoite-cockpit.toml'
      The output should equal 'kinoite-out-kinoite-cockpit'
    End

    It 'derives "kinoite-44-out-kinoite-cockpit" for kinoite-44 + cockpit override'
      When call _bib_out_subdir 'kinoite-44.env' 'kinoite-cockpit.toml'
      The output should equal 'kinoite-44-out-kinoite-cockpit'
    End
  End
End
