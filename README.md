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

- [ ] When server is up it should notify all client.
- [ ] new job should rescan for new chest since server startup
- [ ] add job dependency ? (add output/input to job for chaining them)
- [x] Handle count vs count in recipe if recipe provide more than one item
- [ ] Handle items with nbt
  - [ ] Modify UI (button 1x1 on right, info frame x=4 on bottom)
  - [ ] Add keyCombo over items (Ctrl+key) for frequent job like smelting
- [ ] add pocket computer support for calling jobs remotely and admin server
- [ ] Clean code by segmenting it
- [ ] Handle when user ask too many crafts (log + threshold):
  - Calculate max we can craft ?
  - cut crafts by chunck ?
- [ ] Add installation doc (and script ?)
