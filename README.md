# Hubot VictorOps Adapter

## Description
This Hubot adapter allows your Hubot to join your VictorOps timeline.  You can then address Hubot with timeline chat messages in the usual way:

    @hubot pug bomb 5

## Installation
First, install Hubot according to the instructions: [https://github.com/github/hubot/tree/master/docs](https://github.com/github/hubot/tree/master/docs)

1. Add the VictorOps adapter to your Hubot's dependencies in package.json:

        ...
        "dependencies": {
          "hubot-victorops": ">=0.0.1",
          ...
        }
        ...

1. Run Hubot  with the VictorOps adapter:

        bin/hubot --adapter victorops

## Configuration
Your Hubot will need a login key to connect to VictorOps.  Your Hubot key is available at the "Hubot" link of your VictorOps Integrations page.
Configuration of the key is in an environment variable:

    export HUBOT_VICTOROPS_KEY=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

## Installation alternatives
Rather than edit your Hubot's dependencies, you can install the adapter directly from github:

    npm install git://github.com/victorops/hubot-victorops.git

Or from npmjs.org:

    npm install hubot-victorops

## Copyright

Copyright &copy; 2014 VictorOps, Inc.
