hubot-victorops
===============
Install Hubot according to the instructions: [https://github.com/github/hubot/tree/master/docs](https://github.com/github/hubot/tree/master/docs)

Clone this repo. Then install the VictorOps adapter to Hubot:

    npm install ./hubot-victorops

Settings go in environment variables:

    HUBOT_VICTOROPS_KEY=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    export HUBOT_VICTOROPS_KEY

Run hubot:

    bin/hubot --adapter victorops
