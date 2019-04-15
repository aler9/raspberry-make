
# raspberry-make

raspberry-make is a command-line tool that can be used to build deterministic and ready-to-use OS images for the Raspberry PI, defined by a set of configuration files. It is intended for creating images with pre-defined configuration and software, that can be deployed to headless computers, without the need of following the setup procedure, manually installing software or tweaking with configuration files. This approach leads to a decrease in deployment time, to a decrease in human-related errors, and allows to collect all the configuration files relative to a specific project in a single repository.

raspberry-make is distributed in the form of a Makefile, and makes use of Ansible, a common tool to tweak a system, that follows rules defined in YAML-formatted files.

## Installation and usage

1. Install dependencies:
   * Docker
   * Makefile

2. Download the Makefile and the example configuration:
   ```
   curl -L https://github.com/gswly/raspberry-make/tarball/master | tar zxvf -
   rm README.md LICENSE
   ```

3. Edit `config` to suit your needs.

4. Edit `00base/playbook.yml` to suit your needs. Configuration format is the one of Ansible playbooks, described in their [documentation](https://docs.ansible.com/ansible/latest/user_guide/playbooks.html). It is possible to create as many folders as needed, each with a `playbook.yml` file. Rules will be executed sequentially.

5. Launch:
   ```
   make
   ```
   the image will be available in `build/final.img`.

## Other commands

 * Clean build dir:
   ```
   make clean
   ```

 * Update raspberry-make to latest version:
   ```
   make self-update
   ```

## Links

main image builder
* https://github.com/RPi-Distro/pi-gen

similar
* https://github.com/davidferguson/pibakery
* https://github.com/Scout24/rpi-image-creator

inspired by
* https://github.com/plerup/makeEspArduino
