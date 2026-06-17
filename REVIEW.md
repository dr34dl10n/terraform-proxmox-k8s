# 🔍 Project Review — Issue Tracker

> Created from code review on 2026-06-06

| # | Severity | Issue | Status |
|---|----------|-------|--------|
| 1 | 🔴 Critical | Real API token in `.env` | ✅ OK — `.env` is local-only & gitignored |
| 2 | 🔴 Critical | Real SSH key in `terraform.tfvars.example` | ✅ OK — not a real key |
| 3 | 🟡 Medium | `fisrt-run.log` binary blob in project root | ✅ Fixed — deleted + `*.log` in gitignore |
| 4 | 🟡 Medium | Root-level `terraform.tfstate` not gitignored | ✅ Fixed — deleted + `*.tfstate*` `*.tfplan` in gitignore |
| 5 | 🟡 Medium | IP mismatch README vs NOTES.md (.231 vs .11) | ✅ Fixed — NOTES.md updated to .231/.232/.233 |
| 6 | 🟡 Medium | `template_vm_id` 9000 vs 9001 mismatch | ✅ Fixed — aligned all to 9001 |
| 7 | 🟢 Low | Typo: `fisrt-run.log` | ✅ Fixed — file deleted |
| 8 | 🔴 Critical | `sed` placeholder `__CP_IP__` doesn't match `CP_IP_REPLACE` — kubeadm init would fail | ✅ Fixed — sed now matches `CP_IP_REPLACE` |
| 9 | 🟡 Medium | DRY violation: duplicate VM resource blocks in `main.tf` | ✅ Fixed — refactored to `for_each` with `locals` map |
| 10 | 🟡 Medium | ~90% code duplication in cloud-init CP/worker files | ✅ Fixed — single template + templatefile() + source_raw |
| 11 | 🟢 Low | Unnecessary `count = 1` on control plane resource | ✅ Auto-resolved by #9 refactor (for_each) |
| 12 | 🟡 Medium | Incomplete SSH provider config in `providers.tf` | ✅ Fixed — added `node` block + SSH agent doc |
| 13 | 🟢 Low | No remote state backend (document as limitation?) | ✅ Fixed — documented in providers.tf with backend snippet comment |
| 14 | 🟢 Low | Unused `proxmox_user` variable | ✅ Fixed — removed from variables.tf, tfvars, tfvars.example, NOTES.md |
| 15 | 🟢 Low | `package_upgrade: true` slows VM boot | ✅ Fixed — set to `false` in main.tf locals |
| 16 | 🟢 Low | containerd config written before install (works but fragile) | ✅ Fixed — config moved to runcmd after `apt-get install` |
| 17 | 🟡 Medium | Calico v3.27 may not support K8s v1.31 (needs v3.28+) | ✅ Fixed — Calico bumped to v3.28.0 |
| 18 | 🟢 Low | No JoinConfiguration on workers (style concern) | ✅ Fixed — added JoinConfiguration in cloud-init template + CP_IP_REPLACE sed in join-workers.sh |
| 19 | 🟢 Low | Empty `package.json` / `package-lock.json` files | ✅ Fixed — deleted |
| 20 | 🟢 Low | `.gitignore` gaps | ✅ Fixed — added `*.tfstate.backup`, `*.backup` |
| 21 | 🟡 Medium | Fragile `terraform.tfvars` parsing in shell scripts | ✅ Fixed — scripts/common.sh uses terraform output + awk fallback |
| 22 | 🟢 Low | Wrong state file path in `destroy-cluster.sh` | ✅ Fixed — removed stale `.terraform/terraform.tfstate` check |

---

## Fixes Applied

### Round 1 (items 3–8)

- **3** — Deleted `fisrt-run.log`, added `*.log` to `.gitignore`
- **4** — Deleted root `terraform.tfstate`, added `*.tfstate*` and `*.tfplan` to `.gitignore`
- **5** — Updated 6 IP references in `NOTES.md`: `.11/.12/.13` → `.231/.232/.233`
- **6** — Aligned `template_vm_id` to `9001` in `terraform.tfvars.example` + `README.md`
- **7** — Covered by fix #3 (file deleted)
- **8** — Fixed sed in `scripts/init-control-plane.sh`: `__CP_IP__` → `CP_IP_REPLACE`

### Round 2 (items 17, 22, 12, 9)

- **17** — Bumped Calico v3.27.0 → v3.28.0 in `init-control-plane.sh` + `NOTES.md` (K8s v1.31 compat)
- **22** — Removed stale `.terraform/terraform.tfstate` check in `destroy-cluster.sh`, kept only `terraform.tfstate`
- **12** — Added `node { name, address }` block to SSH provider + documented SSH agent requirement in `providers.tf`
- **9** — Refactored `main.tf`: two duplicate `resource` blocks → single `proxmox_virtual_environment_vm.node` with `for_each = local.all_nodes`. Uses `locals` map (`control_plane_node` + `worker_nodes`) merged via `merge()`. ⚠️ Requires `terraform state mv` or re-apply to migrate existing state.

### Round 3 (items 10, 21; #11 auto-resolved)

- **10** — Replaced two duplicate cloud-init YAML files with single `cloud-init/user-data.yaml.tpl`. Uses Terraform `%{ if is_control_plane }` conditionals for CP-only kubeadm config. `main.tf` renders via `templatefile()` + `source_raw` (no more `source_file` referencing separate YAMLs). Deleted old `control-plane-user-data.yaml` and `worker-user-data.yaml`.
- **21** — Created `scripts/common.sh` shared helper: all 4 scripts now source it instead of inline `grep | sed` parsing. Primary method: `terraform output -json` (robust). Fallback: `awk`-based tfvars parsing. Added `ssh_user` output to `outputs.tf`. Scripts accept CLI args as overrides.
- **11** — Auto-resolved: `count = 1` eliminated by the `for_each` refactor in Round 2 (#9).

### Round 4 (items 13, 14, 15, 16, 18, 19, 20 — all remaining)

- **14** — Removed unused `proxmox_user` variable from `variables.tf`, `terraform.tfvars`, `terraform.tfvars.example`, and `NOTES.md`. API token auth makes this variable redundant.
- **13** — Documented lack of remote state backend in `providers.tf` with a commented-out S3 backend snippet for future use.
- **15** — Changed `package_upgrade` from `true` to `false` in `main.tf` locals. `package_update: true` still runs for security; full upgrade skipped to speed boot.
- **16** — Moved containerd `config.toml` from `write_files` to `runcmd` (after `apt-get install -y containerd`) so apt no longer overwrites our custom config.
- **18** — Added `JoinConfiguration` block to worker cloud-init template (conditioned by `is_control_plane`). Workers now get `/etc/kubeadm/kubeadm-config.yaml` with proper `nodeRegistration` and `cgroup-driver` settings. `join-workers.sh` now runs `sed` to replace `CP_IP_REPLACE` in worker config.
- **19** — Deleted empty `package.json` and `package-lock.json` (no Node.js usage in this project).
- **20** — Added `*.tfstate.backup` and `*.backup` to `.gitignore` for complete coverage of backup state files at any directory level.

Also fixed: Calico v3.27.0 → v3.28.0 in README.md manual mode section, README.md project tree updated to reflect single `user-data.yaml.tpl` and `common.sh`.

## Remaining — Priority Order

✅ **All issues resolved!** No remaining open items.