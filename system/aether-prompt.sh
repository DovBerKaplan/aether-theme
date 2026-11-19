# Aether's two-line bash prompt, sourced from ~/.bashrc (install/install-apps.sh adds the line):
#   ┌──(user㉿host)-[~/dir]
#   └─$
# The frame wears the theme's cyan, the name its blue, a failed command turns the frame red.
[[ $- == *i* ]] || return 0

__aether_prompt() {
  local s=$? frame='\[\e[0;36m\]' name='\[\e[1;34m\]' dir='\[\e[1;37m\]' off='\[\e[0m\]'
  (( s )) && frame='\[\e[0;31m\]'
  local mark='㉿' sign='$'
  (( EUID == 0 )) && { name='\[\e[1;31m\]'; mark='💀'; sign='#'; }
  PS1="\[\e]0;\u@\h: \w\a\]${frame}┌──(${name}\u${mark}\h${frame})-[${dir}\w${frame}]${off}\n${frame}└─${name}${sign}${off} "
}
PROMPT_COMMAND="__aether_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
