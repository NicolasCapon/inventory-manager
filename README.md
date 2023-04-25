# Inventory-manager

Manage your inventory with cc:tweaked
User interface is based of [Basalt](https://basalt.madefor.cc/#/)


## Features

### Inventory system

Request items
dump items to a central inventory


### Crafting

Save recipes
Craft items recursively


### Jobs

Create jobs to manipulate your inventory automatically or by a simple click
Job can include many tasks and can be called regularly or manually.


## Installation

TODO


## TODO

- [ ] finish liveParams features:
    - [x] keyboard navigation
    - [ ] handle frequency on cron job (refactor parallel API as a class)
    - [x] server removeJob option
    - [x] newly added job need server restart to be active -> TEST
    - [x] factorize job/cron methods on server.lua
- [x] Handle count vs count in recipe if recipe provide more than one item
- [ ] Handle items with nbt
- [ ] Handle when user ask too many crafts (log + threshold):
    - Calculate max we can craft ?
    - cut crafts by chunck ?
- [ ] add pocket computer support for calling jobs remotely
- [ ] Clean code by segmenting it
- [ ] Add installation doc (and script ?)
