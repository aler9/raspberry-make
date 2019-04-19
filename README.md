
# raspberry-make

raspberry-make is a command-line tool that can be used to build deterministic and ready-to-use OS images for the Raspberry PI, defined by a set of configuration files. It is intended for creating images with pre-defined configuration and software, that can be deployed to headless computers, without the need of following the setup procedure, manually installing software or tweaking with configuration files. This approach leads to a decrease in deployment time, to a decrease in human-related errors, and allows to collect all the configuration files relative to a specific project in a single repository.

Features:
* compatible with multiple Linux distros, as it depends only on docker
* building happens in a isolated docker container
* all build stages are cached and thus reprocessed only if needed
* allows to set an arbitrary image size

raspberry-make is distributed in the form of a Makefile, and makes use of Ansible, a common tool to remotely tweak a system, that follows rules defined in YAML-formatted files.

## Installation and usage

1. Install dependencies:
   * Docker
   * Makefile

2. Create an empty folder and download needed files:
   ```
   curl -L https://github.com/gswly/raspberry-make/tarball/master | tar zxvf - --strip-components=1
   rm README.md LICENSE
   ```

3. Edit `config` to suit your needs.

4. Edit `00base/playbook.yml` to suit your needs. Configuration files are Ansible playbooks, whose format is documented [here](https://docs.ansible.com/ansible/latest/user_guide/playbooks.html). It is possible to create as many folders as needed, each with a `playbook.yml` file. Folders are opened in alphabetical order, and rules are executed sequentially.

5. Launch:
   ```
   make
   ```
   the resulting image will be available in `build/output.img`.

## Other commands

 * Update raspberry-make to the latest version:
   ```
   make self-update
   ```

## Links

main image builder
* https://github.com/RPi-Distro/pi-gen

similar software
* https://github.com/davidferguson/pibakery
* https://github.com/Scout24/rpi-image-creator

inspired by
* https://github.com/plerup/makeEspArduino
