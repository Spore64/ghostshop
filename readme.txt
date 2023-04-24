variables:

local usedLayout = 0		-- saves which shop layout is used for the ghost shop

-- general quality
local itemQuality = {}		-- stores the differnet item qualities. The table position correlates with the shopLayout table position + 1

-- things which need to get reset upon ending a run
-- item storage 
local storedItems = {		-- stores the items from the last run	
	{},			-- items of the quality 0
	{},			-- items of the quality 1
	{},			-- items of the quality 2
	{},			-- items of the quality 3
	{}			-- items of the quality 4
}
local storedCoopItems = {
	{},			-- items of player 2
	{},			-- items of player 3
	{}			-- items of player 4
}
local temporaryStored = {	-- stores the items for the players upon entering a new floor (used in case one or more players die as a coop baby or in the Mother Chase)
	{},			-- player 
	{},			-- coop1
	{},			-- coop2
	{}			-- coop3
}

-- item prices
local prePrice = {}		-- keeps track of the amount of the normal price in the pre flipped shop
local postPrice = {}		-- keeps track of the amount of the normal price in the post flipped shop
local shoppingList = {}		-- keeps track of the items you bought
local backupListOne = {}	-- keeps track of the items you bought overall in your run. Stores the items you bought 1 time in a row
local backupListTwo = {} 	-- keeps track of the items you bought overall in your run. Stores the items you bought 2 or more times in a row

local flipped = 1		-- keeps track if a player flipped the items and on which flipped site we are on currently 1 = normal 2 = flipped
local preFlipped = {}		-- stores the items of the regular layout of the ghost shop
local postFlipped = {}		-- stores the items of the version of layout of the ghost shop once the player uses the Flip item

local preAddRestockPrice = {}	-- keeps track of the amount of money which should be added on top of the normal price in the pre flipped shop
local postAddRestockPrice = {}	-- keeps track of the amount of money which should be added on top of the normal price in the post flipped shop

local seenCollectibles = {}	-- keeps track of all the items spawned in in a run

functions with save/load relevance:

-- MC_POST_PLAYER_INIT , start found in line 544 --
function GhostShop:onStart()
	-- GameState = json.decode(Isaac.LoadModData(GhostShop)) -- decodes the data from the savefile (returns a lua table)
	GameState = json.decode(GhostShop:LoadData()) -- decodes the data from the savefile (returns a lua table)
	-- print("Player")
	if GameState.seenItems == nil then GameState.seenItems = {} end					-- stores the id's from all items the players have seen during their run
 
	if GameState.savedItems1 == nil then GameState.savedItems1 = {} end				-- stores the id's of the current items the players have 
	if GameState.savedItems2 == nil then GameState.savedItems2 = {} end
	if GameState.savedItems3 == nil then GameState.savedItems3 = {} end
	if GameState.savedItems4 == nil then GameState.savedItems4 = {} end
	if GameState.savedItems5 == nil then GameState.savedItems5 = {} end

	if GameState.backUpItems1 == nil then GameState.backUpItems1 = {} end				-- stores the id's of the last set items the players had while winning, dying or exiting the game before starting a new run (only get filled at the start of a new run)
	if GameState.backUpItems2 == nil then GameState.backUpItems2 = {} end
	if GameState.backUpItems3 == nil then GameState.backUpItems3 = {} end
	if GameState.backUpItems4 == nil then GameState.backUpItems4 = {} end
	if GameState.backUpItems5 == nil then GameState.backUpItems5 = {} end

	if GameState.coopItems1 == nil then GameState.coopItems1 = {} end				-- stores the id's of the current items the coop players have (important for the item pool of the coop ghosts)
	if GameState.coopItems2 == nil then GameState.coopItems2 = {} end
	if GameState.coopItems3 == nil then GameState.coopItems3 = {} end

	if GameState.backUpCoopItems1 == nil then GameState.backUpCoopItems1 = {} end			-- stores the id's of the last set items the players had while winning, dying or exiting the game before starting a new run
	if GameState.backUpCoopItems2 == nil then GameState.backUpCoopItems2 = {} end
	if GameState.backUpCoopItems3 == nil then GameState.backUpCoopItems3 = {} end

	if GameState.preFlippedItems == nil then GameState.preFlippedItems = {} end			-- stores the id's from the default layout of the ghost shop
	if GameState.postFlippedItems == nil then GameState.postFlippedItems = {} end			-- stores the id's of the flipped layout (only get's filled once the player actually uses the Flip item (to prevent items from being removeed from the pool without the possibility to excess them)

	if GameState.prePrice == nil then GameState.prePrice = {} end					-- stores the current price for each of the individuell items of the default shop layout
	if GameState.postPrice == nil then GameState.postPrice = {} end					-- stores the current price for each of the individuell items of the flipped shop layout

	if GameState.preAddRestockPrice == nil then GameState.preAddRestockPrice = {} end		-- stores the current price for each of the individuell items of the default shop layout 
	if GameState.postAddRestockPrice == nil then GameState.postAddRestockPrice = {} end		-- stores the current price for each of the individuell items of the default shop layout
	
	if GameState.shoppingList == nil then GameState.shoppingList = {} end				-- stores which items the players bought in the last run
	if GameState.backupShoppingListOne == nil then GameState.backupShoppingListOne = {} end		-- stores which items have been bought twice in a row		(used to determine the price increase of the item)
	if GameState.backupShoppingListTwo == nil then GameState.backupShoppingListTwo = {} end		-- stores which items have been bought thrice or more in a row	(used to determine the price increase of the item)

	if GameState.backUpQuality == nil then GameState.backUpQuality = {} end				-- stores the determined quality of the default layout

	if GameState.backUpLayout == nil then GameState.backUpLayout = 0 end				-- stores which layout is currentlyused to spawn the items

	if GameState.deathBonus == nil then GameState.deathBonus = 0 end				-- stores the bonus the player gets from completing floors without dying (bonuses can increase the quality of the individuel shop slots)
	if GameState.winBonus == nil then GameState.winBonus = 0 end					-- stores the bonus the player gets from beating end game bosses (bonuses can increase the quality of the individuel shop slots)

end
GhostShop:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, GhostShop.onStart)

-- MC_POST_GAME_STARTED , start found in line 593--
function GhostShop:onNewStart(bool)

	-- print("Game Start")
	
	if bool == false then		-- the start of a complete new game/run
		local deathBonus = GameState.deathBonus - 1		-- depends on the amount of stages the player cleared before dying. Increases the item quality
		local winBonus = GameState.winBonus			-- depends on which end boss the player managed to beat. Will reset deathbonus to 0.
		luckyBonus = 0						-- depends which layout will be used in the end

		-- create a back up table This way the json table can be updated on the fly once the player loses or closes the game
		GameState.backupItems1 = GameState.savedItems1
		GameState.backupItems2 = GameState.savedItems2
		GameState.backupItems3 = GameState.savedItems3
		GameState.backupItems4 = GameState.savedItems4
		GameState.backupItems5 = GameState.savedItems5

		-- store the items from the json table in the regular table
		storedItems[1] = GameState.savedItems1
		storedItems[2] = GameState.savedItems2
		storedItems[3] = GameState.savedItems3
		storedItems[4] = GameState.savedItems4
		storedItems[5] = GameState.savedItems5

		-- do the same for the coop items
		GameState.backUpCoopItems1 = GameState.coopItems1
		GameState.backUpCoopItems2 = GameState.coopItems2
		GameState.backUpCoopItems3 = GameState.coopItems3

		storedCoopItems[1] = GameState.backUpCoopItems1
		storedCoopItems[2] = GameState.backUpCoopItems2
		storedCoopItems[3] = GameState.backUpCoopItems3

		-- reset which shop was entered
		NormalShopVisit = false
		GhostShopVisit = false

		-- choose the new layout
		-- get the rng
		local ghostRNG = RNG()
		ghostRNG:SetSeed(game:GetSeeds():GetStartSeed(), 0)

		-- at the start choose which layout is going to be used for the run
		-- currently not mod friendly
		local layoutRNG = (ghostRNG:RandomInt(100) + 1)
		if layoutRNG <= 5 then		-- unlucky layout
			usedLayout = 1
		elseif layoutRNG <= 35 then	-- normal layouts
			usedLayout = 2
		elseif layoutRNG <= 65 then	-- normal layouts
			usedLayout = 3
		elseif layoutRNG <= 96 then
			usedLayout = 4
		else				-- lucky layout
			usedLayout = 5
			luckyBonus = 4
		end
		-- save the itemQuality table for later
		GameState.backUpLayout = usedLayout
		
		-- reset the quality table
		itemQuality = {}
		-- get the quality of the items which will be available 
		-- but first get the slot which has always a quality 4 or lower item
		local maxQuality = false
		fixedQuality = ghostRNG:RandomInt(shopLayouts[usedLayout][1]) + 1	-- position depends on the set num of items set on the 1st position of the choosen layout

		for i = 1, shopLayouts[usedLayout][1] do 		-- the amount of times we do this depends on the num of item set in first position of the used shopLayout
					
			local qualityRange = (ghostRNG:RandomInt(25) + 1)	-- This allows the player to slightly affect the quality of the items down the line
			-- determine the quality
			if (qualityRange + deathBonus + winBonus + luckyBonus) <= 5 then
				-- the item quality will be 0
				table.insert(itemQuality,1)					-- (table, position, quality)
			elseif (qualityRange + deathBonus + winBonus + luckyBonus) > 5 
			and (qualityRange + deathBonus + winBonus + luckyBonus) <= 10 then
				-- the item quality will be 1
				table.insert(itemQuality,2)
			elseif (qualityRange + deathBonus + winBonus + luckyBonus) > 10 
			and (qualityRange + deathBonus + winBonus + luckyBonus) <= 15 then
				-- the item quality will be 2
				table.insert(itemQuality,3)
			elseif (qualityRange + deathBonus + winBonus + luckyBonus) > 15 
			and (qualityRange + deathBonus + winBonus + luckyBonus) <= 20 then
				-- the item quality will be 3
				table.insert(itemQuality,4)
			elseif (qualityRange + deathBonus + winBonus) > 20 then
				-- the item quality will be 4
				table.insert(itemQuality,5)
				if usedLayout ~= 5 then
					maxQuality = true		-- should prevent the 'fixedQuality' to add another quality 5 slot
				end
			end
		end

		-- check if i is equal to the position in fixedQuality. This will be the guaranted slot
		for i = 1, shopLayouts[usedLayout][1] do
			if maxQuality == false
			and i == fixedQuality then
				itemQuality[i] = 5
			end
		end
		-- save the itemQuality table for later
		GameState.backUpQuality = itemQuality
		-- now reset the bonus since they don't have a use anymore
		GameState.deathBonus = 0
		GameState.winBonus = 0

		-- reset the store sign position table
		storeSigns = {}
		storeSignsFlipped = {}

		-- reset the restock synergy
		preAddRestockPrice = {}
		postAddRestockPrice = {}

		for i = 1, shopLayouts[usedLayout][1] do 
			preAddRestockPrice[i] = 0
			postAddRestockPrice[i] = 0
		end

		-- keep track of the items the player bought last run
		shoppingList = GameState.shoppingList
		backupListOne = GameState.backupShoppingListOne
		backupListTwo = GameState.backupShoppingListTwo
		-- at the beginning of a new run the shoppingList (the items you bought in your last run have to be matched with the items ...
		-- from the other two shopping table 
		
		if shoppingList[1] ~= nil then			-- first make sure the table isn't empty
			local decoyListOne = {}			-- stores item from the second one which match with the shoppingList
			local decoyListTwo = {}	
			local decoyListThree = {}		
			local readdItems = false 
			
			if backupListOne[1] == nil 
			and backupListTwo[1] == nil then	-- both tables are empty
				backupListOne = shoppingList	-- since they don't contain any items all items from the shoppingList get inserted into the frist backip table

			else	-- we split the items and insert them into the two backup tables
				for j, item in ipairs(shoppingList) do	-- go through each entry of the table
					local inSecondTable = false
					local inFirstTable = false
					-- for each entry of the shoppingList go through the items from the two backup shopping lists

					if backupListTwo[1] ~= nil then
						for k, backupItems in ipairs(backupListTwo) do
							if backupItems == item then
								-- add the item to the decoyListThree table
								table.insert(decoyListThree,1,item)
								-- marked the item id as being found
								inSecondTable = true
							end
						end
					end
					if inSecondTable == false		-- item wasn't in the second backup table
					and backupListOne[1] ~= nil then
						for l, backupItems in ipairs(backupListOne) do
							if backupItems == item then
								-- add the item to the decoyListTwo table
								table.insert(decoyListThree,1,item)
								-- marked the item id as being found
								inFirstTable = true
							end
						end
					end
					if inSecondTable == false
					and inFirstTable == false then
						-- add the item to the decoyListTwo table
						table.insert(decoyListOne,1,item)
					end
				end
				readdItems = true
			end
			if readdItems == true then
				-- reinsert the decoy tables
				backupListOne = decoyListTwo
				backupListTwo = decoyListThree
				-- insert the rest of the items into the first backup table
				if decoyListOne[1] ~= nil then		 	-- make sure the table isn't empty
					for m, item in ipairs(decoyListOne) do	-- go through the rest of the normal list
						table.insert(backupListOne,1,item)
					end
				end
			end
		elseif shoppingList[1] == nil then	-- no items have been bought in the last run
			-- reset both backup tables
			backupListOne = {}
			backupListTwo = {}
		end
		shoppingList = {}

		-- reset the synergie variables just in case
		hasUsedDice = false	-- D6, Eternal D6, D Infinty and Dice Shard
		hasUsedD100 = false	-- extra for D100
		hasUsedFlip = false	-- Flip
		flippedQuality = {}
		GameState.preFlippedItems = {}		
		GameState.postFlippedItems = {}
		flipped = 1
		preFlipped = {}
		postFlipped = {}
		GameState.prePrice = {}		
		GameState.postPrice = {}
		prePrice = {}
		postPrice = {}
		GameState.preAddRestockPrice = {}		
		GameState.postAddRestockPrice = {}
		dontRestock = false
		needsToRestock = false
		hasSteamSale = false
		hasUsedFMN = false
		openNomralShop = false
		shopStayOpen = false
		seenCollectibles = {}
		GameState.seenItems = {}			-- first lets reset it

	elseif bool == true then	-- the run continues
		-- note this might can be done in a way which only does this if the player can still get the ghost shop.
		-- update the regular item table with the backup table to know which items are left
		storedItems[1] = GameState.backupItems1
		storedItems[2] = GameState.backupItems2
		storedItems[3] = GameState.backupItems3
		storedItems[4] = GameState.backupItems4
		storedItems[5] = GameState.backupItems5

		-- update the tables for the coop ghosts
		storedCoopItems[1] = GameState.backUpCoopItems1
		storedCoopItems[2] = GameState.backUpCoopItems2
		storedCoopItems[3] = GameState.backUpCoopItems3

		-- make sure the layout is still in place
		usedLayout = GameState.backUpLayout

		-- make sure the itemQualitye table is still in place
		itemQuality = GameState.backUpQuality

		-- make sure the game knows that the player beat an endgame boss
		if GameState.winBonus ~= 0 then
			hasWon = true
		end

		-- make sure the prices are tracked properly
		prePrice = GameState.prePrice		
		postPrice = GameState.postPrice
		preAddRestockPrice = GameState.preAddRestockPrice	
		postAddRestockPrice = GameState.postAddRestockPrice

		-- make sure spawned items are tracked properly
		preFlipped = GameState.preFlippedItems		
		postFlipped = GameState.postFlippedItems

		-- make sure that the flipped state is tracked properly.
		if preFlipped[(shopLayouts[GameState.backUpLayout][1]) + 1] == -2 then		-- this checks the value for the flipped state which we added in the `Mod.onExit` function
			flipped = 1
		elseif preFlipped[(shopLayouts[GameState.backUpLayout][1]) + 1] == -3 then
			flipped = 2
		end

		-- amke sure to track the ghost signs properly
		if flipped == 1 then
			if storeSigns[1] == nil then
				SpawnGhostSigns = true
			end
		elseif flipped == 2 then
			if storeSignsFlipped[1] == nil then
				SpawnGhostSigns = true
			end
		end

		-- make sure to track which shop was visited or not
		if preFlipped[1] ~= nil then 	-- means the player must have visited the ghost shop
			GhostShopVisit = true
		end

		-- make sure the shoplist ist tracked properly
		shoppingList = GameState.shoppingList
		backupShoppingListOne = GameState.backupShoppingListOne
		backupShoppingListTwo = GameState.backupShoppingListTwo

		-- make sure the seen items are tracked properly
		seenCollectibles = GameState.seenItems
	end
end
GhostShop:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, GhostShop.onNewStart)

-- MC_POST_NEW_LEVEL , start found in line 2170 --
function GhostShop:onNewFloor(_)
	local itemConfig = Isaac.GetItemConfig()
	local level = game:GetLevel()
	local stage = level:GetStage()
	local stageType = level:GetStageType()

	-- only increased the counter if the player hasn't won yet
	if hasWon == false then
		-- print(GameState.deathBonus)
		if GameState.deathBonus == nil then	-- prevents the debug console to print a small error message the first time a player uses the mod
			GameState.deathBonus = 0
		end
		GameState.deathBonus = GameState.deathBonus + 1
	end
	if GameState.winBonus == nil then	-- prevents the debug console to print a small error message the first time a player uses the mod
		GameState.winBonus = 0	
	end

	-- temporary store the items the players have (in case of coop babies or death in the mother chase sequence)
	if game:GetNumPlayers() > 1 then	-- stuff which we do if there are more than 1 player aka coop happens
		for i = 0, (game:GetNumPlayers() - 1) do
			local player = Isaac.GetPlayer(i)
			if player:IsCoopGhost() == false then	-- player is still alive.. in a way
				-- go through all normal items (not optimal I know...)
				-- reset the table we draw later from
				if temporaryStored[(i + 1)][1] ~= nil then	-- there's an item in the table slot!
					temporaryStored[(i + 1)] = {}
				end
				for j = 1, 732 do
					if player:HasCollectible(j) then
				
						if j ~= 43		-- doesn't exist
						and j ~= 59		-- doesn't exist
						and j ~= 61		-- doesn't exist
						and j ~= 235		-- doesn't exist
						and j ~= 666		-- doesn't exist
						and j ~= 238		-- Key Piece 1
						and j ~= 239		-- Key Piece 2
						and j ~= 327		-- Polariod
						and j ~= 328		-- Negative
						and j ~= 550		-- Broken Shovel 1
						and j ~= 551		-- Broken Shovel 2
						and j ~= 552		-- Broken Shovel
						and j ~= 626		-- Knife Piece 1
						and j ~= 668 then	-- Dad's Note 
							-- insert the item in the temporary table
							if temporaryStored[(i + 1)] ~= nil then
								table.insert(temporaryStored[(i + 1)],1, j)
							end
						end
					end
				end	
			end
		end
	else					-- stuff we do normaly
		local player = Isaac.GetPlayer(0)	-- as no coop is happening we just need to get one player
		-- check if the player is in the Mines or Ashpit
		if (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B)
		and stage == LevelStage.STAGE2_2
		and player:HasCollectible(CollectibleType.COLLECTIBLE_KNIFE_PIECE_1) then	-- Mother chase only spawns when you have knife piece 1
			-- go through all normal items
			for j = 1, 732 do
				if player:IsCoopGhost() == false
				and player:HasCollectible(j) then
				
					if j ~= 43		-- doesn't exist
					and j ~= 59		-- doesn't exist
					and j ~= 61		-- doesn't exist
					and j ~= 235		-- doesn't exist
					and j ~= 666		-- doesn't exist
					and j ~= 238		-- Key Piece 1
					and j ~= 239		-- Key Piece 2
					and j ~= 327		-- Polariod
					and j ~= 328		-- Negative
					and j ~= 550		-- Broken Shovel 1
					and j ~= 551		-- Broken Shovel 2
					and j ~= 552		-- Broken Shovel
					and j ~= 626		-- Knife Piece 1
					and j ~= 668 then	-- Dad's Note 
						-- insert the item in the temporary table
						table.insert(temporaryStored[1],1, j)
						print(temporaryStored[1][1])
					end
				end
			end
		end
	end
end
GhostShop:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, GhostShop.onNewFloor)

-- MC_NPC_UPDATE, start found in line 2260 --
function GhostShop:onEndBossKill(entity)
	local data = entity:GetData()
	local motherKill = false
	if entity:IsDead() -- is it dead?
	and data.Died == nil then -- did it already die
		data.Died = true -- well now it is dead	
		-- check which boss was killed	
		if entity.Type == EntityType.ENTITY_THE_LAMB then
			GameState.winBonus = 7
		elseif entity.Type == EntityType.ENTITY_ISAAC and entity.Variant == 1 then			-- blue baby
			if hasWon == false then	-- hasn't killed Hush
				GameState.winBonus = 5
			end
		elseif entity.Type == EntityType.ENTITY_MEGA_SATAN_2 then
			GameState.winBonus = 12
		elseif entity.Type == EntityType.ENTITY_HUSH then
			GameState.winBonus = 15
		elseif entity.Type == EntityType.ENTITY_DELIRIUM then
			GameState.winBonus = 20
		elseif entity.Type == EntityType.ENTITY_MOTHER then
			if entity.Variant == 10 then
				GameState.winBonus = 20		
			else
				 motherKill = true
			end
		elseif entity.Type == EntityType.ENTITY_DOGMA then
			GameState.winBonus = 15
		elseif entity.Type == EntityType.ENTITY_BEAST then
			GameState.winBonus = 20
		end
		-- print(GameState.winBonus)
		if motherKill == false then		-- prevents the first phase of mother to nullify the death bonus
			GameState.deathBonus = 1 	-- prevents the death bonus to be negative
			hasWon = true
		end
	end
end
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_THE_LAMB)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_ISAAC)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_MEGA_SATAN_2)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_HUSH)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_DELIRIUM)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_MOTHER)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_DOGMA)
GhostShop:AddCallback(ModCallbacks.MC_NPC_UPDATE, GhostShop.onEndBossKill, EntityType.ENTITY_BEAST)

-- MC_PRE_GAME_EXIT, MC_POST_GAME_END , start found in line 2702--
function GhostShop:onExit(_)
	local itemConfig = Isaac.GetItemConfig()
	local room = game:GetRoom()
	local roomType = room:GetType()

	local level = game:GetLevel()
	local stage = level:GetStage()
	local stageType = level:GetStageType()

	-- reset the Gamestate tables
	GameState.savedItems1 = {}
	GameState.savedItems2 = {}
	GameState.savedItems3 = {}
	GameState.savedItems4 = {}
	GameState.savedItems5 = {}
	-- coop ghosts
	GameState.coopItems1 = {}
	GameState.coopItems2 = {}
	GameState.coopItems3 = {}

	-- update the preFlipped tables with the items which are currently in them
	GameState.preFlippedItems = preFlipped		
	GameState.postFlippedItems = postFlipped
	-- also save which side we are currently flipped to
	if preFlipped[1] ~= nil then	-- we make sure the item were spawned in the ghost shop
		if preFlipped[(shopLayouts[GameState.backUpLayout][1]) + 1] == nil then
			if flipped == 1 then		
				table.insert(preFlipped, -2)
			elseif flipped == 2 then	
				table.insert(preFlipped, -3)
			end
		else
			if flipped == 1 then		
				preFlipped[(shopLayouts[GameState.backUpLayout][1]) + 1] = -2
			elseif flipped == 2 then	
				preFlipped[(shopLayouts[GameState.backUpLayout][1]) + 1] = -3
			end
		end
	end

	-- update the seenItems
	GameState.seenItems = seenCollectibles		-- then refill the table with the seen items in the current run
	
	-- update the different shopping lists
	GameState.shoppingList = shoppingList
	GameState.backupShoppingListOne = backupListOne
	GameState.backupShoppingListTwo = backupListTwo

	-- update the different item prices
	GameState.prePrice = prePrice	
	GameState.postPrice = postPrice
	GameState.preAddRestockPrice = preAddRestockPrice	
	GameState.postAddRestockPrice = postAddRestockPrice

	-- store the position of the store signs	-- needs flip compatibilty !!
	if storeSigns[1] ~= nil then
		GameState.savedStoreSigns = storeSigns
		-- print(GameState.savedStoreSigns[1])
	end


	-- update the Gamestate tables with the items the player currently has
	for i = 0, (game:GetNumPlayers() - 1) do
		local player = Isaac.GetPlayer(i)
		local playerData = player:GetData()

		-- store the character id from coop players for the lil coop ghosts (mod compatibility only). This allows to know which characters were used in the last run
		if i == 1 then		-- player 2
			table.insert(GameState.coopItems1, 1, player:GetPlayerType())
		elseif i == 2 then	-- player 3
			table.insert(GameState.coopItems2, 1, player:GetPlayerType())
		elseif i == 3 then	-- player 4
			table.insert(GameState.coopItems3, 1, player:GetPlayerType())
		end

		-- check if the player dies in the mother chase	(currently doesn' seem to work?)
		if (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B)
		and stage == LevelStage.STAGE2_2
		-- and room:IsMirrorWorld() == true then	
		and GetDimension(level) == 1 then	-- should detect the Mine Chase (thanks to Wolfsauge)

			-- go through their corresponding temporary table and check their quality
			for k, itemID in ipairs(temporaryStored[(i + 1)]) do

				-- check which quality the item has
				if itemConfig:GetCollectible(itemID).Quality == 0 then
					table.insert(GameState.savedItems1,1, itemID)	-- insert the item into the quality 0 table
				elseif itemConfig:GetCollectible(itemID).Quality == 1 then
					table.insert(GameState.savedItems2,1, itemID)	-- insert the item into the quality 1 table
				elseif itemConfig:GetCollectible(itemID).Quality == 2 then
					table.insert(GameState.savedItems3,1, itemID)	-- insert the item into the quality 2 table
				elseif itemConfig:GetCollectible(itemID).Quality == 3 then
					table.insert(GameState.savedItems4,1, itemID)	-- insert the item into the quality 3 table
				elseif itemConfig:GetCollectible(itemID).Quality == 4 then
					table.insert(GameState.savedItems5,1, itemID)	-- insert the item into the quality 4 table
				end
				-- store the items from coop players again for the lil coop ghosts
				if i == 1 then		-- player 2
					table.insert(GameState.coopItems1, itemID)
				elseif i == 2 then	-- player 3
					table.insert(GameState.coopItems2, itemID)
				elseif i == 3 then	-- player 4
					table.insert(GameState.coopItems3, itemID)
				end
			end
		else
			-- check if the player is a coop ghost
			if player:IsCoopGhost() == false then
				-- go through all normal items
				for j = 1, 732 do
					if player:HasCollectible(j) then
				
						if j ~= 43		-- doesn't exist
						and j ~= 59		-- doesn't exist
						and j ~= 61		-- doesn't exist
						and j ~= 235		-- doesn't exist
						and j ~= 666		-- doesn't exist
						and j ~= 238		-- Key Piece 1
						and j ~= 239		-- Key Piece 2
						and j ~= 327		-- Polariod
						and j ~= 328		-- Negative
						and j ~= 550		-- Broken Shovel 1
						and j ~= 551		-- Broken Shovel 2
						and j ~= 552		-- Broken Shovel
						and j ~= 626		-- Knife Piece 1
						and j ~= 668 then	-- Dad's Note 
							-- check which quality the item has
							if itemConfig:GetCollectible(j).Quality == 0 then
								table.insert(GameState.savedItems1,1, j)	-- insert the item into the quality 0 table
							elseif itemConfig:GetCollectible(j).Quality == 1 then
								table.insert(GameState.savedItems2,1, j)	-- insert the item into the quality 1 table
							elseif itemConfig:GetCollectible(j).Quality == 2 then
								table.insert(GameState.savedItems3,1, j)	-- insert the item into the quality 2 table
							elseif itemConfig:GetCollectible(j).Quality == 3 then
								table.insert(GameState.savedItems4,1, j)	-- insert the item into the quality 3 table
							elseif itemConfig:GetCollectible(j).Quality == 4 then
								table.insert(GameState.savedItems5,1, j)	-- insert the item into the quality 4 table
							end
							-- store the items from coop players again for the lil coop ghosts
							if i == 1 then		-- player 2
								table.insert(GameState.coopItems1, j)
							elseif i == 2 then	-- player 3
								table.insert(GameState.coopItems2, j)
							elseif i == 3 then	-- player 4
								table.insert(GameState.coopItems3, j)
							end
						end
					end
				end
			else		-- ...so the player is a coop ghost
				-- go through their corresponding temporary table and check their quality
				for k, itemID in ipairs(temporaryStored[(i + 1)]) do
					-- check which quality the item has
					if itemConfig:GetCollectible(itemID).Quality == 0 then
						table.insert(GameState.savedItems1,1, itemID)	-- insert the item into the quality 0 table
					elseif itemConfig:GetCollectible(itemID).Quality == 1 then
						table.insert(GameState.savedItems2,1, itemID)	-- insert the item into the quality 1 table
					elseif itemConfig:GetCollectible(itemID).Quality == 2 then
						table.insert(GameState.savedItems3,1, itemID)	-- insert the item into the quality 2 table
					elseif itemConfig:GetCollectible(itemID).Quality == 3 then
						table.insert(GameState.savedItems4,1, itemID)	-- insert the item into the quality 3 table
					elseif itemConfig:GetCollectible(itemID).Quality == 4 then
						table.insert(GameState.savedItems5,1, itemID)	-- insert the item into the quality 4 table
					end
					-- store the items from coop players again for the lil coop ghosts
					if i == 1 then		-- player 2
						table.insert(GameState.coopItems1, itemID)
					elseif i == 2 then	-- player 3
						table.insert(GameState.coopItems2, itemID)
					elseif i == 3 then	-- player 4
						table.insert(GameState.coopItems3, itemID)
					end
				end
			end
		end
	end
	-- save the data
	Isaac.SaveModData(GhostShop, json.encode(GameState))	-- encodes the data
end
GhostShop:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, GhostShop.onExit)
GhostShop:AddCallback(ModCallbacks.MC_POST_GAME_END, GhostShop.onExit)