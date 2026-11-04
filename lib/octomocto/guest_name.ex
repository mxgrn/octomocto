defmodule Octomocto.GuestName do
  @moduledoc """
  The random ocean names of guests, such as "Salty Squid". The session keeps
  only the indices of the two words (see `OctomoctoWeb.GuestName`), thus a
  guest cannot set any other text. A new user gets such a name as the
  display name too (see `Octomocto.Accounts.User`).

  Add new words only at the end of the lists. A change of the order or a
  removed word changes the names of the guests that have it.
  """

  @adjectives ~w(
    Salty Soggy Splashy Bubbly Briny Foamy Sandy Shiny Drifty Sleepy Wobbly
    Sneaky Curious Dizzy Jolly Brave Polite Fancy Tiny Mighty Giggly Sunny
    Breezy Snappy Cheerful Humble Fluffy Speedy Clever Cozy Swirly Zippy
    Wavy Misty Stormy Frosty Glowing Sparkly Twinkly Pearly Silvery Golden
    Rusty Dreamy Bouncy Wiggly Squishy Slippery Chubby Plucky Peppy Perky
    Chirpy Bashful Bold Calm Daring Eager Gentle Happy Lucky Merry Nimble
    Quirky Rowdy Sassy Silly Spunky Witty Zesty Glittery Cosmic Dapper
    Fearless Fuzzy Grumpy Hasty Lazy Loopy Nifty Noble Proud Quiet Rapid
    Restless Snoozy Spiffy Spotty Stripy Swift Tidy Toasty Wandering Wise
    Zany Lofty Hungry Jumpy Twirly Velvet Crispy Mellow Frisky Gleeful
  )

  @nouns ~w(
    Octopus Squid Narwhal Walrus Otter Seal Penguin Pufferfish Jellyfish
    Starfish Lobster Crab Clam Oyster Barnacle Dolphin Orca Whale Manta
    Seahorse Turtle Anchovy Sardine Plankton Coral Sponge Pelican Albatross
    Shrimp Prawn Krill Eel Stingray Shark Urchin Anemone Nautilus Cuttlefish
    Mackerel Herring Tuna Marlin Swordfish Halibut Flounder Cod Grouper
    Snapper Clownfish Angelfish Blowfish Goby Barracuda Beluga Manatee
    Dugong Puffin Gull Cormorant Gannet Tern Petrel Sandpiper Mussel Scallop
    Cockle Limpet Whelk Conch Sunfish Lionfish Pipefish Wrasse Parrotfish
    Triggerfish Remora Anglerfish Frogfish Seadragon Sculpin Blenny Kraken
    Moray Tarpon Wahoo Snook Kingfish Bonito Copepod
    Isopod Dory Haddock Pollock Sturgeon Salmon Trout
  )

  @doc "A random name."
  def random_name, do: name(random())

  @doc "Random indices of a name."
  def random do
    {Enum.random(0..(length(@adjectives) - 1)), Enum.random(0..(length(@nouns) - 1))}
  end

  @doc "The name of the indices, or nil when they are not valid."
  def name({adjective, noun}) when is_integer(adjective) and is_integer(noun) do
    with a when is_binary(a) <- at(@adjectives, adjective),
         n when is_binary(n) <- at(@nouns, noun) do
      a <> " " <> n
    end
  end

  def name(_indices), do: nil

  defp at(_words, index) when index < 0, do: nil
  defp at(words, index), do: Enum.at(words, index)
end
