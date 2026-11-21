# Aether's two-line bash prompt, sourced from ~/.bashrc (install/install-apps.sh adds the line):
#   ┌──(user⟨distro⟩host)-[~/dir]
#   └─$
# The frame wears the theme's cyan, the name its blue, a failed command turns the frame red.
# The mark is the running distro's own Nerd-Font logo, read once from /etc/os-release —
# clones on other distros wear their own; anything unrecognised falls back to Tux,
# and root trades the logo for the skull.
[[ $- == *i* ]] || return 0

__aether_mark() (
  . /etc/os-release 2>/dev/null
  case "$ID${ID_LIKE:+ $ID_LIKE}" in
    *neon*)     printf '\uF331' ;; # KDE neon
    *kali*)     printf '\uF327' ;; # the real dragon, not the borrowed Korean K
    *parrot*)   printf '\uF329' ;;
    *manjaro*)  printf '\uF312' ;;
    *endeavour*) printf '\uF322' ;;
    *artix*)    printf '\uF31F' ;;
    *garuda*)   printf '\uF337' ;;
    *arch*)     printf '\uF303' ;;
    *fedora*)   printf '\uF30A' ;;
    *suse*)     printf '\uF314' ;;
    *nixos*)    printf '\uF313' ;;
    *alpine*)   printf '\uF300' ;;
    *mint*)     printf '\uF30E' ;;
    *elementary*) printf '\uF309' ;;
    *pop*)      printf '\uF32A' ;;
    *void*)     printf '\uF32E' ;;
    *zorin*)    printf '\uF32F' ;;
    *gentoo*)   printf '\uF30D' ;;
    *slackware*) printf '\uF318' ;;
    *deepin*)   printf '\uF321' ;;
    *rocky*)    printf '\uF32B' ;;
    *alma*)     printf '\uF31D' ;;
    *centos*)   printf '\uF304' ;;
    *redhat*|*rhel*) printf '\uF316' ;;
    *raspbian*|*raspberry*) printf '\uF315' ;;
    *devuan*)   printf '\uF307' ;;
    *aosc*)     printf '\uF301' ;;
    *mageia*)   printf '\uF310' ;;
    *solus*)    printf '\uF32D' ;;
    *kubuntu*)  printf '\uF333' ;;
    *ubuntu*)   printf '\uF31B' ;;
    *mx*)       printf '\uF33F' ;;
    *debian*)   printf '\uF306' ;;
    *)          printf '\uF31A' ;; # Tux catches the rest
  esac
)
__AETHER_MARK=$(__aether_mark)

__aether_prompt() {
  local s=$? frame='\[\e[0;36m\]' name='\[\e[1;34m\]' dir='\[\e[1;37m\]' off='\[\e[0m\]'
  (( s )) && frame='\[\e[0;31m\]'
  local mark=$__AETHER_MARK sign='$'
  (( EUID == 0 )) && { name='\[\e[1;31m\]'; mark='💀'; sign='#'; }
  PS1="\[\e]0;\u@\h: \w\a\]${frame}┌──(${name}\u${mark}\h${frame})-[${dir}\w${frame}]${off}\n${frame}└─${name}${sign}${off} "
}
PROMPT_COMMAND="__aether_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
