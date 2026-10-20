export const TOOLS = [
  "docker",
  "ansible",
  "kubernetes",
  "linux",
  "git",
  "terraform",
  "jenkins",
  "aws",
] as const;

export type Tool = (typeof TOOLS)[number];

export const TOOL_META: Record<
  Tool,
  { label: string; blurb: string }
> = {
  docker: { label: "Docker", blurb: "Conteneurs" },
  ansible: { label: "Ansible", blurb: "Automatisation" },
  kubernetes: { label: "Kubernetes", blurb: "Orchestration" },
  linux: { label: "Linux", blurb: "Systèmes" },
  git: { label: "Git", blurb: "Versioning" },
  terraform: { label: "Terraform", blurb: "Infrastructure" },
  jenkins: { label: "Jenkins", blurb: "CI/CD" },
  aws: { label: "AWS", blurb: "Cloud" },
};
