
# Added by app-coder: VS Code Desktop beside code-server and JetBrains, first in the list.
# See https://registry.coder.com/modules/coder/vscode-desktop
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  folder   = "/workspaces"
  order    = 0
}
