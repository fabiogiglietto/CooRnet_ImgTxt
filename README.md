# CooRnet_ImgTxt

Simple r scripts that reuse some [CooRnet](https://coornet.org/) code and logic to detect the coordinated network of Facebook or Instagram accounts that repeatedly share images with identical text in a short period of time.

Given a link to a CSV returned by a [CrowdTangle Search](https://help.crowdtangle.com/en/articles/3873721-crowdtangle-search-faq) export and a coordination interval, returns a list that include a dataframe of coordinated accounts, a graphml file that can be opened and visualized in Gephi and a variable q that represents the threshold number of rapid-shares repetition used to label coordinated accounts.

Please use blueapp.r for Facebook or rainbowapp.r for Instagram.

## Future works

Whenever I have time, I plan to improve this project as follows:

1.  Merge the two scripts to analyze cross-platform coordinated networks;

2.  Port the script to a function;

3.  Port some other functions from CooRnet (e.g. get_clusters/components for an overview of detected networks and most frequently associated imgtxt).

Help on this (or other) tasks is very well welcome!

If you have spare time and want to contribute just drop me a message!
